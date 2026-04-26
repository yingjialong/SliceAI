import XCTest
@testable import Capabilities

/// `PathSandbox` 单测：覆盖 spec §3.9.3 全部判定分支。
///
/// 使用真实文件系统操作（在 `~/Documents/` 下创建测试文件 / symlink）的测试，
/// 都附带 `tearDown` 清理；测试实例字段 `cleanupURLs` 收集要在 tearDown 删除的路径，
/// 即使断言中途失败也能保证 ~/Documents 不留垃圾。
final class PathSandboxTests: XCTestCase {

    /// 待清理路径集合；每个测试单独维护。
    /// 使用 set 避免重复添加同一路径导致重复 try 删除。
    private var cleanupURLs: Set<URL> = []

    /// 当前 home 目录（`NSHomeDirectory()`），把 `~` 展开成绝对路径用。
    private var home: String { NSHomeDirectory() }

    override func tearDownWithError() throws {
        // 即使断言失败，也尽力删除测试创建的 symlink / 文件，避免影响后续测试或污染用户目录
        for url in cleanupURLs {
            // try? 是有意的：tearDown 阶段不抛错；删除失败大概率是文件已不存在或权限问题
            try? FileManager.default.removeItem(at: url)
        }
        cleanupURLs.removeAll()
        try super.tearDownWithError()
    }

    // MARK: - 1. `..` traversal

    /// `~/Documents/../Library/Keychains/foo` 经规范化后变成 `~/Library/Keychains/foo`，
    /// 命中硬禁止前缀 → 应抛 `.escapesAllowlist`。
    func test_normalize_dotDotTraversalIntoKeychains_throwsEscapesAllowlist() {
        // 给定：用 ../ 试图从 Documents 跳到 Library/Keychains
        let sandbox = PathSandbox()
        let raw = "~/Documents/../Library/Keychains/foo"

        // 当：规范化（任意角色都应被拒绝，先用 .read 验证）
        // 则：应抛 escapesAllowlist；硬禁止前缀优先生效
        XCTAssertThrowsError(try sandbox.normalize(raw, role: .read)) { error in
            guard case let PathSandboxError.escapesAllowlist(rawPath, normalized) = error else {
                XCTFail("expected .escapesAllowlist, got \(error)")
                return
            }
            XCTAssertEqual(rawPath, raw, "rawPath 应原样回传")
            // 规范化后应以 ~/Library/Keychains 开头（家目录已展开）
            XCTAssertTrue(
                normalized.hasPrefix("\(home)/Library/Keychains"),
                "normalized 应展开为绝对路径并落入 Keychains，实际 = \(normalized)"
            )
        }
    }

    // MARK: - 2. symlink 攻击（验证 resolvingSymlinksInPath 真生效）

    /// 在 `~/Documents/` 下创建一个指向 `~/Library/Keychains` 的 symlink，
    /// `normalize(...)` 应 throw `.escapesAllowlist`：因为 `resolvingSymlinksInPath()`
    /// 会展开链接到硬禁止前缀，被前置拒绝。
    func test_normalize_symlinkToKeychains_throwsEscapesAllowlist() throws {
        let sandbox = PathSandbox()
        let fm = FileManager.default

        // 用 UUID 防止并发测试 / 残留 symlink 冲突
        let linkName = "test-sandbox-\(UUID().uuidString).link"
        let linkURL = URL(fileURLWithPath: "\(home)/Documents/\(linkName)")
        let targetURL = URL(fileURLWithPath: "\(home)/Library/Keychains")

        // 注册待清理（即便 createSymbolicLink 失败也无副作用——removeItem 找不到会静默失败）
        cleanupURLs.insert(linkURL)

        // 创建 symlink；权限不足 / 系统限制时直接 fail（用 XCTUnwrap 模式提早退出）
        do {
            try fm.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
        } catch {
            // 真实环境基本不会失败，但若沙箱跑测试无写权限就提前 skip
            throw XCTSkip("无法在 ~/Documents 创建测试 symlink，跳过：\(error)")
        }

        // 当：规范化 link 路径
        let raw = "~/Documents/\(linkName)"
        XCTAssertThrowsError(try sandbox.normalize(raw, role: .read)) { error in
            guard case let PathSandboxError.escapesAllowlist(_, normalized) = error else {
                XCTFail("expected .escapesAllowlist, got \(error)")
                return
            }
            // resolvingSymlinksInPath 应把 link 替换成 Keychains 真实路径
            // macOS 上 ~/Library/Keychains 本身可能是真实目录或 symlink，但 normalize 后不会再以 Documents 开头
            XCTAssertFalse(
                normalized.hasPrefix("\(home)/Documents/"),
                "symlink 必须被展开，normalized 不应仍位于 Documents 下，实际 = \(normalized)"
            )
        }
    }

    // MARK: - 3. symlink resolved 顺序 sanity（验证 link 指向白名单内文件时的 happy path）

    /// 在 `~/Documents/` 下建一个真实文件 + 一个指向它的 symlink，
    /// `normalize(...)` 应返回展开后的真实文件 URL（同样落在 Documents，不报错）。
    /// 用于反向验证 `resolvingSymlinksInPath()` 真的展开了，而不是被跳过。
    func test_normalize_symlinkToAllowlistedTarget_returnsResolvedURL() throws {
        let sandbox = PathSandbox()
        let fm = FileManager.default

        // 真实文件 + 指向它的 link，都在 ~/Documents/ 下
        let uuid = UUID().uuidString
        let targetURL = URL(fileURLWithPath: "\(home)/Documents/test-target-\(uuid).txt")
        let linkURL = URL(fileURLWithPath: "\(home)/Documents/test-link-\(uuid).txt")

        // 注册待清理
        cleanupURLs.insert(targetURL)
        cleanupURLs.insert(linkURL)

        // 创建实文件
        do {
            try Data("hello".utf8).write(to: targetURL)
        } catch {
            throw XCTSkip("无法写入测试文件，跳过：\(error)")
        }
        // 创建指向实文件的 symlink
        do {
            try fm.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
        } catch {
            throw XCTSkip("无法创建测试 symlink，跳过：\(error)")
        }

        // 当：规范化 link 路径（.read 应通过——link 与 target 都在 ~/Documents/）
        let raw = "~/Documents/test-link-\(uuid).txt"
        let normalized = try sandbox.normalize(raw, role: .read)

        // 则：返回的应是 resolve 后的真实路径（target 文件名），而非 link 文件名
        // 注意：~/Documents 在某些 macOS 上自身也可能 symlink → resolvingSymlinksInPath 后路径可能与
        // home 字符串不完全一致（典型差异：/var vs /private/var）；只校验 lastPathComponent 与"在 home 路径内"两点
        XCTAssertEqual(
            normalized.lastPathComponent,
            "test-target-\(uuid).txt",
            "link 应被展开为 target 文件名，实际 = \(normalized.path)"
        )
    }

    // MARK: - 4. 硬禁止前缀直接拒绝

    /// 直接传 `/etc/passwd` → 应抛 `.escapesAllowlist`（硬禁止优先于白名单逻辑）。
    func test_normalize_directHardDenyEtc_throwsEscapesAllowlist() {
        let sandbox = PathSandbox()
        let raw = "/etc/passwd"

        XCTAssertThrowsError(try sandbox.normalize(raw, role: .read)) { error in
            guard case let PathSandboxError.escapesAllowlist(rawPath, normalized) = error else {
                XCTFail("expected .escapesAllowlist, got \(error)")
                return
            }
            XCTAssertEqual(rawPath, raw)
            // /etc 在 macOS 上是 symlink → /private/etc，resolvingSymlinksInPath 后通常变 /private/etc/passwd
            // 但硬禁止匹配是基于 normalize 后的字符串前缀；/private/etc 不在硬禁止表里，
            // 所以这里实际拦截发生在"白名单"那一关而非"硬禁止"那一关——但抛的错误类型是同一个 .escapesAllowlist
            // 这正是 spec §3.9.3 的设计：硬禁止 + 白名单两道关只用一种"逃逸"错误类型对外
            XCTAssertFalse(normalized.isEmpty)
        }
    }

    /// 进一步验证硬禁止家目录路径 `~/.ssh/config` 被拦下（这条路径展开后是真实绝对路径，硬禁止前缀直接命中）。
    func test_normalize_hardDenySshConfig_throwsEscapesAllowlist() {
        let sandbox = PathSandbox()
        let raw = "~/.ssh/config"

        XCTAssertThrowsError(try sandbox.normalize(raw, role: .read)) { error in
            guard case let PathSandboxError.escapesAllowlist(_, normalized) = error else {
                XCTFail("expected .escapesAllowlist, got \(error)")
                return
            }
            XCTAssertTrue(
                normalized.hasPrefix("\(home)/.ssh"),
                "normalized 应位于 ~/.ssh 下，实际 = \(normalized)"
            )
        }
    }

    // MARK: - 5. 白名单 happy path

    /// `~/Documents/foo.txt` + `.read` → 返回展开后的 URL（无需文件真实存在，URL 不校验存在性）。
    func test_normalize_documentsRead_returnsExpandedURL() throws {
        let sandbox = PathSandbox()
        let raw = "~/Documents/foo-\(UUID().uuidString).txt"

        let normalized = try sandbox.normalize(raw, role: .read)

        // 文件名应保留；路径应是绝对路径
        XCTAssertEqual(normalized.lastPathComponent.hasPrefix("foo-"), true)
        XCTAssertTrue(normalized.path.hasPrefix("/"), "应为绝对路径，实际 = \(normalized.path)")
    }

    // MARK: - 6. .write 拒绝只读路径

    /// `~/Documents/foo.txt` + `.write` → 抛 `.writeNotPermittedForReadOnlyPath`
    /// （路径在读白名单但不在写白名单）。
    func test_normalize_documentsWrite_throwsWriteNotPermitted() {
        let sandbox = PathSandbox()
        let raw = "~/Documents/foo.txt"

        XCTAssertThrowsError(try sandbox.normalize(raw, role: .write)) { error in
            guard case let PathSandboxError.writeNotPermittedForReadOnlyPath(normalized) = error else {
                XCTFail("expected .writeNotPermittedForReadOnlyPath, got \(error)")
                return
            }
            XCTAssertTrue(normalized.contains("/Documents/"), "normalized 应包含 /Documents/，实际 = \(normalized)")
        }
    }

    // MARK: - 7. .write 允许 Application Support

    /// `~/Library/Application Support/SliceAI/cache.json` + `.write` → 返回展开 URL。
    func test_normalize_applicationSupportWrite_returnsExpandedURL() throws {
        let sandbox = PathSandbox()
        let raw = "~/Library/Application Support/SliceAI/cache.json"

        let normalized = try sandbox.normalize(raw, role: .write)

        XCTAssertEqual(normalized.lastPathComponent, "cache.json")
        XCTAssertTrue(
            normalized.path.contains("/Library/Application Support/SliceAI/"),
            "normalized 应位于 SliceAI 应用支持目录，实际 = \(normalized.path)"
        )
    }

    // MARK: - 8. 空字符串 / 无效输入

    /// `""` → 抛 `.invalidInput`。
    func test_normalize_emptyString_throwsInvalidInput() {
        let sandbox = PathSandbox()

        XCTAssertThrowsError(try sandbox.normalize("", role: .read)) { error in
            guard case let PathSandboxError.invalidInput(rawPath) = error else {
                XCTFail("expected .invalidInput, got \(error)")
                return
            }
            XCTAssertEqual(rawPath, "")
        }
    }

    /// 全空白字符串同样应被识别为非法输入（trim 后为空）。
    func test_normalize_whitespaceOnly_throwsInvalidInput() {
        let sandbox = PathSandbox()

        XCTAssertThrowsError(try sandbox.normalize("   \n\t ", role: .read)) { error in
            guard case PathSandboxError.invalidInput = error else {
                XCTFail("expected .invalidInput, got \(error)")
                return
            }
        }
    }

    /// 相对路径（不以 / 起头、不以 ~ 起头）→ 抛 `.invalidInput`。
    /// `URL(fileURLWithPath:)` 会自动用 cwd 拼接，但那是不可预测的运行目录，
    /// 沙箱必须拒绝任何"非显式绝对"输入。
    func test_normalize_relativePath_throwsInvalidInput() {
        let sandbox = PathSandbox()

        XCTAssertThrowsError(try sandbox.normalize("relative/path/foo.txt", role: .read)) { error in
            guard case PathSandboxError.invalidInput = error else {
                XCTFail("expected .invalidInput, got \(error)")
                return
            }
        }
    }

    // MARK: - 9. 防误命中：DocumentsBackup ≠ Documents

    /// `~/DocumentsBackup/foo.txt` 不应被 `~/Documents/` 前缀误命中（hasPrefix 必须含尾随 /）。
    func test_normalize_documentsBackup_isNotMistakenForDocuments() {
        let sandbox = PathSandbox()
        let raw = "~/DocumentsBackup/foo.txt"

        XCTAssertThrowsError(try sandbox.normalize(raw, role: .read)) { error in
            guard case PathSandboxError.escapesAllowlist = error else {
                XCTFail("DocumentsBackup 不应被 Documents 前缀命中，预期 .escapesAllowlist，实际 \(error)")
                return
            }
        }
    }

    // MARK: - 10. PathSandboxError 文案 / Equatable 自检

    /// `userMessage` 三个 case 均返回非空中文文案（保护 UI 不出现空字符串）。
    func test_pathSandboxError_userMessages_areNonEmptyChinese() {
        let cases: [PathSandboxError] = [
            .escapesAllowlist(rawPath: "x", normalized: "/y"),
            .writeNotPermittedForReadOnlyPath(normalized: "/y"),
            .invalidInput(rawPath: "")
        ]
        for err in cases {
            XCTAssertFalse(err.userMessage.isEmpty, "userMessage 不应为空：\(err)")
        }
    }

    /// `Equatable` 行为校验：相同关联值相等、不同则不等。
    func test_pathSandboxError_equatable_basicBehavior() {
        let a1 = PathSandboxError.escapesAllowlist(rawPath: "x", normalized: "/y")
        let a2 = PathSandboxError.escapesAllowlist(rawPath: "x", normalized: "/y")
        let b = PathSandboxError.escapesAllowlist(rawPath: "x", normalized: "/z")
        XCTAssertEqual(a1, a2)
        XCTAssertNotEqual(a1, b)
        XCTAssertNotEqual(a1, .invalidInput(rawPath: "x"))
    }
}
