import Foundation
import SliceCore
import XCTest
@testable import Capabilities

/// Phase 1 M2 Task 7：五个内置 ContextProvider 的行为测试
final class ContextProviderTests: XCTestCase {

    // MARK: - Fixtures

    /// 构造测试用选区快照。
    ///
    /// - Parameter text: 选中文字。
    /// - Returns: 可直接传给 provider.resolve 的 `SelectionSnapshot`。
    private func makeSelection(text: String = "seed selection") -> SelectionSnapshot {
        SelectionSnapshot(
            text: text,
            source: .accessibility,
            length: text.count,
            language: nil,
            contentType: nil
        )
    }

    /// 构造测试用前台 app 快照。
    ///
    /// - Parameters:
    ///   - title: 前台窗口标题。
    ///   - url: 前台浏览器 URL。
    /// - Returns: 可直接传给 provider.resolve 的 `AppSnapshot`。
    private func makeApp(
        title: String? = "Front Window",
        url: URL? = URL(string: "https://example.com/current")
    ) -> AppSnapshot {
        AppSnapshot(
            bundleId: "com.example.front",
            name: "Front App",
            url: url,
            windowTitle: title
        )
    }

    /// 构造测试用 ContextRequest。
    ///
    /// - Parameters:
    ///   - provider: provider 注册名。
    ///   - args: 透传给 provider 的参数。
    /// - Returns: `ContextRequest`。
    private func makeRequest(
        provider: String,
        args: [String: String] = [:]
    ) -> ContextRequest {
        ContextRequest(
            key: ContextKey(rawValue: "ctx"),
            provider: provider,
            args: args,
            cachePolicy: .none,
            requiredness: .required
        )
    }

    // MARK: - Provider behavior

    /// selection provider 应直接返回 seed 中的选区文本。
    func test_selectionProvider_returnsSeedSelection() async throws {
        let provider = SelectionContextProvider()

        let value = try await provider.resolve(
            request: makeRequest(provider: "selection"),
            seed: makeSelection(text: "hello selected text"),
            app: makeApp()
        )

        XCTAssertEqual(provider.name, "selection")
        XCTAssertEqual(value, .text("hello selected text"))
    }

    /// app.windowTitle provider 应返回前台 app 快照中的窗口标题。
    func test_windowTitleProvider_returnsFrontAppTitle() async throws {
        let provider = AppWindowTitleContextProvider()

        let value = try await provider.resolve(
            request: makeRequest(provider: "app.windowTitle"),
            seed: makeSelection(),
            app: makeApp(title: "Design Doc - SliceAI")
        )

        XCTAssertEqual(provider.name, "app.windowTitle")
        XCTAssertEqual(value, .text("Design Doc - SliceAI"))
    }

    /// app.url provider 应返回前台 app 快照中的 URL 字符串。
    func test_appURLProvider_returnsFrontAppURL() async throws {
        let provider = AppURLContextProvider()
        let url = try XCTUnwrap(URL(string: "https://example.com/a?b=1"))

        let value = try await provider.resolve(
            request: makeRequest(provider: "app.url"),
            seed: makeSelection(),
            app: makeApp(url: url)
        )

        XCTAssertEqual(provider.name, "app.url")
        XCTAssertEqual(value, .text("https://example.com/a?b=1"))
    }

    /// clipboard.current provider 应返回注入 pasteboard 读取器产出的文本。
    func test_clipboardProvider_returnsInjectedPasteboardText() async throws {
        let provider = ClipboardCurrentContextProvider(readString: {
            "clipboard injected text"
        })

        let value = try await provider.resolve(
            request: makeRequest(provider: "clipboard.current"),
            seed: makeSelection(),
            app: makeApp()
        )

        XCTAssertEqual(provider.name, "clipboard.current")
        XCTAssertEqual(value, .text("clipboard injected text"))
    }

    /// file.read provider 应通过 PathSandbox 规范化后读取白名单内文件。
    func test_fileReadProvider_readsWhitelistedFile() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let fileURL = temporaryDirectory.appendingPathComponent("note.txt")
        try "file context text".write(to: fileURL, atomically: true, encoding: .utf8)
        let sandbox = PathSandbox(userAllowlist: [temporaryDirectory.path])
        let provider = FileReadContextProvider(sandbox: sandbox)

        let value = try await provider.resolve(
            request: makeRequest(provider: "file.read", args: ["path": fileURL.path]),
            seed: makeSelection(),
            app: makeApp()
        )

        XCTAssertEqual(provider.name, "file.read")
        XCTAssertEqual(value, .text("file context text"))
    }

    /// file.read provider 应拒绝 PathSandbox 硬禁止路径，即使用户 allowlist 覆盖该目录。
    func test_fileReadProvider_rejectsHardDeniedPath() async throws {
        let sandbox = PathSandbox(userAllowlist: ["/etc/"])
        let provider = FileReadContextProvider(sandbox: sandbox)

        do {
            _ = try await provider.resolve(
                request: makeRequest(provider: "file.read", args: ["path": "/etc/passwd"]),
                seed: makeSelection(),
                app: makeApp()
            )
            XCTFail("硬禁止路径应被拒绝")
        } catch let error as PathSandboxError {
            guard case .escapesAllowlist(let rawPath, _) = error else {
                XCTFail("应抛 escapesAllowlist，实际：\(error)")
                return
            }
            XCTAssertEqual(rawPath, "/etc/passwd")
        } catch {
            XCTFail("应抛 PathSandboxError，实际：\(error)")
        }
    }

    /// 五个 provider 的静态权限推导应与 Task 7 计划一致。
    func test_contextProviders_inferPermissions() throws {
        XCTAssertEqual(SelectionContextProvider.inferredPermissions(for: [:]), [])
        XCTAssertEqual(AppWindowTitleContextProvider.inferredPermissions(for: [:]), [])
        XCTAssertEqual(AppURLContextProvider.inferredPermissions(for: [:]), [])
        XCTAssertEqual(ClipboardCurrentContextProvider.inferredPermissions(for: [:]), [.clipboard])
        XCTAssertEqual(
            FileReadContextProvider.inferredPermissions(for: ["path": "~/Docs/a.md"]),
            [.fileRead(path: "~/Docs/a.md")]
        )
    }
}
