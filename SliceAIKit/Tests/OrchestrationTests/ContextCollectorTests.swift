import Foundation
import SliceCore
import XCTest
@testable import Orchestration

/// Task 5: `ContextCollector` 平铺并发实现的测试矩阵
///
/// 覆盖 plan 测试矩阵 6 + 边界 / Equatable 用例：
/// 1. happy path：5 provider 并发全部成功 → contexts 5 项 + failures 空
/// 2. required 失败 → throw `.context(.requiredFailed(key:, underlying:))`
/// 3. optional 失败 → 进 failures + 主流程其他成功项不丢
/// 4. timeout → throw `.context(.timeout(key:))`（required 路径）
/// 5. registry 缺 provider → required 抛 `.providerNotFound(id:)`
/// 6. provider 抛非 SliceError → 包装为 `.context(.requiredFailed)`，underlying 是 SliceError
final class ContextCollectorTests: XCTestCase {

    // MARK: - Fixture builders

    /// 构造最小 ExecutionSeed（与 ExecutionEngineTests 一致风格，不引入耦合）
    private func makeSeed() -> ExecutionSeed {
        let snapshot = SelectionSnapshot(
            text: "context collector test",
            source: .accessibility,
            length: 22,
            language: nil,
            contentType: nil
        )
        let app = AppSnapshot(
            bundleId: "com.test.app",
            name: "Test App",
            url: nil,
            windowTitle: nil
        )
        return ExecutionSeed(
            invocationId: UUID(),
            selection: snapshot,
            frontApp: app,
            screenAnchor: .zero,
            timestamp: Date(),
            triggerSource: .floatingToolbar,
            isDryRun: false
        )
    }

    /// 构造一个 required ContextRequest
    private func makeRequest(
        keyName: String,
        provider: String,
        requiredness: Requiredness = .required
    ) -> ContextRequest {
        ContextRequest(
            key: ContextKey(rawValue: keyName),
            provider: provider,
            args: [:],
            cachePolicy: .none,
            requiredness: requiredness
        )
    }

    // MARK: - 1. Happy path：5 个 provider 并发成功

    /// 5 个 mock provider 并发执行；contexts 含 5 项、failures 空、resolvedAt ≥ seed.timestamp
    func test_resolve_happyPath_5providersConcurrent() async throws {
        let names = (0..<5).map { "p\($0)" }
        let providers: [String: any ContextProvider] = Dictionary(uniqueKeysWithValues: names.map { name in
            (name, MockSuccessProvider(name: name, value: .text("v_\(name)")))
        })
        let registry = ContextProviderRegistry(providers: providers)
        let collector = ContextCollector(registry: registry)
        let seed = makeSeed()
        let requests = names.map { makeRequest(keyName: "k_\($0)", provider: $0) }

        let result = try await collector.resolve(seed: seed, requests: requests)

        XCTAssertEqual(result.contexts.values.count, 5, "5 个 provider 应全部成功")
        XCTAssertTrue(result.failures.isEmpty, "happy path failures 必空")
        for name in names {
            let key = ContextKey(rawValue: "k_\(name)")
            XCTAssertEqual(result.contexts[key], .text("v_\(name)"))
        }
        XCTAssertGreaterThanOrEqual(result.resolvedAt, seed.timestamp, "resolvedAt 应 ≥ trigger timestamp")
    }

    /// 边界：requests 为空 → 立刻返回空 contexts + 空 failures
    func test_resolve_emptyRequests_returnsEmptyBag() async throws {
        let registry = ContextProviderRegistry(providers: [:])
        let collector = ContextCollector(registry: registry)
        let result = try await collector.resolve(seed: makeSeed(), requests: [])

        XCTAssertTrue(result.contexts.values.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
    }

    // MARK: - 2. Required 失败 → throw

    /// 1 个 required provider 抛错 → 整个 resolve throw `.context(.requiredFailed(key:, underlying:))`
    func test_resolve_requiredFailure_throwsRequiredFailed() async {
        let badKey = "bad.required"
        let goodKey = "good.optional"
        let providers: [String: any ContextProvider] = [
            "bad": MockFailureProvider(name: "bad", error: .selection(.axEmpty)),
            "good": MockSuccessProvider(name: "good", value: .text("ok"))
        ]
        let registry = ContextProviderRegistry(providers: providers)
        let collector = ContextCollector(registry: registry)
        let requests = [
            makeRequest(keyName: badKey, provider: "bad", requiredness: .required),
            makeRequest(keyName: goodKey, provider: "good", requiredness: .optional)
        ]

        do {
            _ = try await collector.resolve(seed: makeSeed(), requests: requests)
            XCTFail("required 失败应该 throw")
        } catch let err as SliceError {
            // 必须是 .context(.requiredFailed(key:, underlying:)) 形态
            guard case .context(let ctxErr) = err,
                  case .requiredFailed(let key, let underlying) = ctxErr else {
                XCTFail("expected .context(.requiredFailed), got \(err)")
                return
            }
            XCTAssertEqual(key, ContextKey(rawValue: badKey))
            XCTAssertEqual(underlying, .selection(.axEmpty), "underlying 应保留原始 SliceError")
        } catch {
            XCTFail("expected SliceError, got \(error)")
        }
    }

    // MARK: - 3. Optional 失败 → failures map

    /// 1 个 optional 抛错 + 其他 required 成功 → contexts 含成功项 + failures[key] 是包装的 SliceError
    func test_resolve_optionalFailure_writesToFailuresMap() async throws {
        let optKey = "opt.fail"
        let okKey = "ok.success"
        let providers: [String: any ContextProvider] = [
            "opt": MockFailureProvider(name: "opt", error: .provider(.unauthorized)),
            "ok": MockSuccessProvider(name: "ok", value: .text("done"))
        ]
        let registry = ContextProviderRegistry(providers: providers)
        let collector = ContextCollector(registry: registry)
        let requests = [
            makeRequest(keyName: optKey, provider: "opt", requiredness: .optional),
            makeRequest(keyName: okKey, provider: "ok", requiredness: .required)
        ]

        let result = try await collector.resolve(seed: makeSeed(), requests: requests)

        // 成功项保留
        XCTAssertEqual(result.contexts.values.count, 1)
        XCTAssertEqual(result.contexts[ContextKey(rawValue: okKey)], .text("done"))

        // failures 写入 optional 失败
        XCTAssertEqual(result.failures.count, 1)
        let captured = result.failures[ContextKey(rawValue: optKey)]
        XCTAssertNotNil(captured, "optional 失败应进 failures map")
        // optional 路径保留原始 SliceError 形态（不被包装为 requiredFailed），便于 prompt 模板降级
        XCTAssertEqual(captured, .provider(.unauthorized))
    }

    // MARK: - 4. Timeout → throw .context(.timeout(key:))

    /// provider sleep 远超注入 timeout（50ms）→ 触发 timeout
    ///
    /// 用 SlowProvider sleep 5s（>>50ms timeout 阈值，留两个数量级 margin 抗 CI 调度抖动）
    /// + required 触发 throw。注入 50ms timeout 让 happy 路径在数百 ms 内完成；
    /// 仅当 fix 退化（timeout 不触发）时测试才会退到 5s 慢路径（信息量更大）。
    func test_resolve_timeout_throwsTimeoutForRequired() async {
        let key = "slow.req"
        let providers: [String: any ContextProvider] = [
            "slow": MockSlowProvider(name: "slow", sleepSeconds: 5.0)
        ]
        let registry = ContextProviderRegistry(providers: providers)
        // 注入 50ms timeout（默认 5s）以加速测试；mock sleep 5s 远大于 timeout 保证 race 必胜
        let collector = ContextCollector(registry: registry, defaultTimeoutNanoseconds: 50_000_000)
        let requests = [makeRequest(keyName: key, provider: "slow", requiredness: .required)]

        let start = Date()
        do {
            _ = try await collector.resolve(seed: makeSeed(), requests: requests)
            XCTFail("timeout 应该 throw")
        } catch let err as SliceError {
            // .context(.requiredFailed(key:, underlying: .context(.timeout(key:))))
            // 形态：required 路径会再包一层 requiredFailed
            guard case .context(let ctx) = err else {
                XCTFail("expected .context(...), got \(err)")
                return
            }
            // 接受两种形态：
            // (a) ctx == .timeout(key:)
            // (b) ctx == .requiredFailed(key:, underlying: .context(.timeout(key:)))
            // 当前实现走 (b)：classifyFailure 对 required 统一包成 requiredFailed
            switch ctx {
            case .timeout(let k):
                XCTAssertEqual(k, ContextKey(rawValue: key))
            case .requiredFailed(let k, let underlying):
                XCTAssertEqual(k, ContextKey(rawValue: key))
                guard case .context(.timeout(let innerKey)) = underlying else {
                    XCTFail("underlying 应是 .context(.timeout), got \(underlying)")
                    return
                }
                XCTAssertEqual(innerKey, ContextKey(rawValue: key))
            case .providerNotFound:
                XCTFail("不应是 providerNotFound")
            }
        } catch {
            XCTFail("expected SliceError, got \(error)")
        }

        // 验证耗时在合理上限内（~50ms timeout，留 1s buffer 应对 CI 抖动）
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "timeout 应在 50ms 阈值附近触发，实际 \(elapsed)s")
    }

    // MARK: - 5. Registry 缺 provider

    /// required 请求的 provider 在 registry 找不到 → throw `.providerNotFound`（包装在 requiredFailed 中）
    func test_resolve_providerNotFound_required_throws() async {
        let registry = ContextProviderRegistry(providers: [:])
        let collector = ContextCollector(registry: registry)
        let requests = [makeRequest(keyName: "k", provider: "ghost", requiredness: .required)]

        do {
            _ = try await collector.resolve(seed: makeSeed(), requests: requests)
            XCTFail("缺 provider 应该 throw")
        } catch let err as SliceError {
            guard case .context(let ctx) = err else {
                XCTFail("expected .context(...), got \(err)")
                return
            }
            // 当前实现 classifyFailure(required) 把 .providerNotFound 包成 .requiredFailed(underlying: .providerNotFound)
            // 测试接受两种形态：
            // (a) ctx == .providerNotFound(id:)（未来若实现简化）
            // (b) ctx == .requiredFailed(underlying: .context(.providerNotFound))（当前实现）
            switch ctx {
            case .providerNotFound(let id):
                XCTAssertEqual(id, "ghost")
            case .requiredFailed(_, let underlying):
                guard case .context(.providerNotFound(let id)) = underlying else {
                    XCTFail("underlying 应是 .context(.providerNotFound), got \(underlying)")
                    return
                }
                XCTAssertEqual(id, "ghost")
            case .timeout:
                XCTFail("不应是 timeout")
            }
        } catch {
            XCTFail("expected SliceError, got \(error)")
        }
    }

    /// optional 请求 provider 找不到 → 写入 failures，主流程继续
    func test_resolve_providerNotFound_optional_writesToFailures() async throws {
        let registry = ContextProviderRegistry(providers: [
            "ok": MockSuccessProvider(name: "ok", value: .text("v"))
        ])
        let collector = ContextCollector(registry: registry)
        let optKey = "opt.ghost"
        let okKey = "ok"
        let requests = [
            makeRequest(keyName: optKey, provider: "ghost", requiredness: .optional),
            makeRequest(keyName: okKey, provider: "ok", requiredness: .required)
        ]

        let result = try await collector.resolve(seed: makeSeed(), requests: requests)

        XCTAssertEqual(result.contexts.values.count, 1)
        XCTAssertEqual(result.contexts[ContextKey(rawValue: okKey)], .text("v"))

        let captured = result.failures[ContextKey(rawValue: optKey)]
        XCTAssertEqual(captured, .context(.providerNotFound(id: "ghost")))
    }

    // MARK: - 6. 非 SliceError 底层错误的包装

    /// provider 抛 URLError → 包装为 `.context(.requiredFailed(key:, underlying: someSliceError))`
    func test_resolve_underlyingNonSliceError_wrapsToSliceError() async {
        let key = "url.err"
        let url = URLError(.badServerResponse)
        let providers: [String: any ContextProvider] = [
            "url": MockNonSliceErrorProvider(name: "url", error: url)
        ]
        let registry = ContextProviderRegistry(providers: providers)
        let collector = ContextCollector(registry: registry)
        let requests = [makeRequest(keyName: key, provider: "url", requiredness: .required)]

        do {
            _ = try await collector.resolve(seed: makeSeed(), requests: requests)
            XCTFail("URLError 应该被包装后 throw")
        } catch let err as SliceError {
            guard case .context(.requiredFailed(let outerKey, let underlying)) = err else {
                XCTFail("expected .context(.requiredFailed), got \(err)")
                return
            }
            XCTAssertEqual(outerKey, ContextKey(rawValue: key))
            // underlying 必须是 SliceError（而不是再 throw 原 URLError）
            // 实现细节：当前用 .provider(.networkTimeout) 作为通用 wrapper（见 ContextCollector 注释）
            XCTAssertEqual(underlying, .provider(.networkTimeout),
                           "非 SliceError 底层错误应被包装为 .provider(.networkTimeout)")
        } catch {
            XCTFail("expected SliceError, got \(error)")
        }
    }

    // MARK: - 并发独立性：一个慢 + 多个快，快的不被慢的拖累

    /// 一个 optional 慢 provider（sleep 0.1s 触发 timeout）+ 多个快 required → 验证 group 取消传播：
    /// required 都成功后整个 resolve 不必等到慢的超时返回——但是 optional 失败仍会进 failures。
    ///
    /// **当前实现**：`for try await` 顺序消费 group，等待**所有**子任务完成；optional timeout
    /// 也会等满注入的 timeout 时长。这是 plan 接受的语义（D-17 强调"无 DAG"而非"先完成的尽快返回"），
    /// 因此测试只验证：optional 慢 provider timeout 后进 failures + 快 required 全成功。
    /// 注入 50ms timeout + 5s mock sleep（数量级 margin 抗 CI 调度抖动）让 happy 路径在 ~50ms
    /// 内完成；仅当 fix 退化时退到 5s 慢路径。
    func test_resolve_optionalSlowProvider_doesNotBlockEarlyButRecordsTimeout() async throws {
        let providers: [String: any ContextProvider] = [
            "slow": MockSlowProvider(name: "slow", sleepSeconds: 5.0),
            "fast1": MockSuccessProvider(name: "fast1", value: .text("a")),
            "fast2": MockSuccessProvider(name: "fast2", value: .text("b"))
        ]
        let registry = ContextProviderRegistry(providers: providers)
        // 注入 50ms timeout（默认 5s）以加速测试；optional 慢路径会触发 timeout
        let collector = ContextCollector(registry: registry, defaultTimeoutNanoseconds: 50_000_000)
        let requests = [
            makeRequest(keyName: "slow.opt", provider: "slow", requiredness: .optional),
            makeRequest(keyName: "k1", provider: "fast1", requiredness: .required),
            makeRequest(keyName: "k2", provider: "fast2", requiredness: .required)
        ]

        let start = Date()
        let result = try await collector.resolve(seed: makeSeed(), requests: requests)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result.contexts.values.count, 2)
        XCTAssertEqual(result.contexts[ContextKey(rawValue: "k1")], .text("a"))
        XCTAssertEqual(result.contexts[ContextKey(rawValue: "k2")], .text("b"))

        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures[ContextKey(rawValue: "slow.opt")], .context(.timeout(key: ContextKey(rawValue: "slow.opt"))))

        // optional 超时仍要等满注入的 50ms timeout 才返回（plan 接受的语义）；上限留 buffer
        XCTAssertLessThan(elapsed, 1.0, "整体应在 50ms timeout + 一点 buffer 内返回，实际 \(elapsed)s")
    }
}
