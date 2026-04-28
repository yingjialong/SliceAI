import Foundation
import SliceCore

/// Task 5 Mock — `ContextProvider` 的可配置 Fake
///
/// `ContextProvider` 协议含 `static func inferredPermissions(for:)`，static 不能跨实例自定义，
/// 因此本 Helper 用 **多个具体类型** 覆盖测试场景：
/// - `MockSuccessProvider`：返回固定 ContextValue
/// - `MockFailureProvider`：抛固定 SliceError
/// - `MockNonSliceErrorProvider`：抛 URLError 等"非 SliceError"底层错误
/// - `MockSlowProvider`：sleep 指定秒数后返回（用于 timeout 测试）
///
/// 所有实现都是 `final class`，借助内部状态（actor / Atomics 不在 Foundation 中可直接用，
/// 这里测试场景每实例只调用一次 resolve、不需要并发计数）；name 作为构造参数注入便于一处定义、
/// 通过 ContextProviderRegistry 的 `[name: instance]` 字典完成路由。

// MARK: - 成功路径：返回固定 ContextValue

/// 始终成功并返回构造时配置的 ContextValue
final class MockSuccessProvider: ContextProvider, @unchecked Sendable {
    let name: String
    private let value: ContextValue

    /// 构造成功 mock
    /// - Parameters:
    ///   - name: provider 注册名（与 ContextRequest.provider 对齐）
    ///   - value: resolve 时返回的固定值
    init(name: String, value: ContextValue) {
        self.name = name
        self.value = value
    }

    static func inferredPermissions(for args: [String: String]) -> [Permission] {
        []
    }

    func resolve(
        request: ContextRequest,
        seed: SelectionSnapshot,
        app: AppSnapshot
    ) async throws -> ContextValue {
        // 测试场景：直接返回构造时注入的值
        value
    }
}

// MARK: - 失败路径：抛 SliceError

/// 始终抛构造时配置的 SliceError
final class MockFailureProvider: ContextProvider, @unchecked Sendable {
    let name: String
    private let error: SliceError

    /// 构造失败 mock
    /// - Parameters:
    ///   - name: provider 注册名
    ///   - error: resolve 时抛出的 SliceError
    init(name: String, error: SliceError) {
        self.name = name
        self.error = error
    }

    static func inferredPermissions(for args: [String: String]) -> [Permission] {
        []
    }

    func resolve(
        request: ContextRequest,
        seed: SelectionSnapshot,
        app: AppSnapshot
    ) async throws -> ContextValue {
        // 测试场景：抛已注入的 SliceError，由 ContextCollector catch 后按 requiredness 决定走 throw / failures
        throw error
    }
}

// MARK: - 失败路径：抛非 SliceError（URLError / Foundation 错误）

/// 始终抛构造时配置的非 SliceError 底层错误（用于验证 collector 的"包装为 SliceError"路径）
final class MockNonSliceErrorProvider: ContextProvider, @unchecked Sendable {
    let name: String
    private let error: any Error

    /// 构造非 SliceError mock
    /// - Parameters:
    ///   - name: provider 注册名
    ///   - error: resolve 时抛出的任意 Error（典型：URLError / DecodingError）
    init(name: String, error: any Error) {
        self.name = name
        self.error = error
    }

    static func inferredPermissions(for args: [String: String]) -> [Permission] {
        []
    }

    func resolve(
        request: ContextRequest,
        seed: SelectionSnapshot,
        app: AppSnapshot
    ) async throws -> ContextValue {
        // 测试场景：抛非 SliceError，验证 collector 是否能把它包装回 SliceError
        throw error
    }
}

// MARK: - 慢路径：sleep N 秒后返回（timeout 测试）

/// sleep 指定秒数后才返回（用于触发 ContextCollector 的 timeout 路径）
final class MockSlowProvider: ContextProvider, @unchecked Sendable {
    let name: String
    private let sleepSeconds: Double
    private let value: ContextValue

    /// 构造慢 mock
    /// - Parameters:
    ///   - name: provider 注册名
    ///   - sleepSeconds: resolve 内 sleep 的秒数（典型：>5 触发默认 5s timeout）
    ///   - value: 若没被 timeout 中断则最终返回的值（默认 .text("late")）
    init(name: String, sleepSeconds: Double, value: ContextValue = .text("late")) {
        self.name = name
        self.sleepSeconds = sleepSeconds
        self.value = value
    }

    static func inferredPermissions(for args: [String: String]) -> [Permission] {
        []
    }

    func resolve(
        request: ContextRequest,
        seed: SelectionSnapshot,
        app: AppSnapshot
    ) async throws -> ContextValue {
        // sleep 后返回；ContextCollector 会用 race 模式在外部判定超时 → 取消本任务
        // 用 nanoseconds 避免 Duration API 在测试环境的 backport 兼容性问题
        let nanoseconds = UInt64(sleepSeconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
        return value
    }
}
