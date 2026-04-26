import Foundation

/// 文件路径访问沙箱：规范化 → 硬禁止前缀拦截 → 白名单匹配 → 角色（读/写）校验。
///
/// 参见 spec §3.9.3。本类型在 M2 阶段提供纯静态 API；Phase 1 / 2 才接入
/// `ContextCollector` / `OutputDispatcher` 的真实路径输入路径。放在 Capabilities/SecurityKit
/// 而非 Orchestration，是因为 SecurityKit 是跨执行引擎的基础设施。
///
/// **规范化顺序约定**：
/// ```
/// URL(fileURLWithPath: raw)
///   .resolvingSymlinksInPath()    // 必须先展开 symlink，否则攻击者可以用软链跳出白名单
///   .standardizedFileURL          // 再消除 .. 与重复 /
/// ```
/// `standardizedFileURL` **不**展开 symlink，单独使用无法防住"在白名单目录里建一个指向 Keychains 的链接"
/// 这一类绕过；因此顺序固定，调用方不应自行调换。
///
/// **硬禁止前缀**优先于白名单生效——即使用户把 `~/Library/Keychains` 加入 allowlist，
/// 请求依然会被拒绝。
///
/// **线程安全**：`PathSandbox` 仅读取启动时注入的常量数据（默认前缀 + 用户 allowlist），
/// 自身无可变状态；所有 API 都是 pure function，可在任意线程并发调用，因此声明为 `Sendable`。
public struct PathSandbox: Sendable {

    /// 路径访问角色：读 vs 写。`.write` 走更严格的子集判定。
    public enum AccessRole: Sendable, Equatable {
        /// 只读访问；允许全部默认白名单 + 用户附加白名单。
        case read
        /// 写入访问；仅允许 `~/Library/Application Support/SliceAI/**` 与用户附加白名单。
        case write
    }

    // MARK: - 默认白名单与硬禁止常量

    /// 默认允许读取的目录前缀（**带尾随 `/`**，确保 `hasPrefix` 不会把
    /// `~/DocumentsBackup` 误判为 `~/Documents` 的子路径）。
    /// 元素仍含 `~`，`normalizedDefaultReadPrefixes` 在初始化时把它们展开为绝对路径。
    private static let defaultReadAllowlistTilde: [String] = [
        "~/Documents/",
        "~/Desktop/",
        "~/Downloads/",
        "~/Library/Application Support/SliceAI/"
    ]

    /// 默认允许写入的目录前缀（**带尾随 `/`**，理由同上）。
    /// 仅 SliceAI 应用支持目录可写；其他读取目录默认只读。
    private static let defaultWriteAllowlistTilde: [String] = [
        "~/Library/Application Support/SliceAI/"
    ]

    /// 硬禁止前缀（**带尾随 `/`**）：永远拒绝，无视用户配置 / 角色。
    /// 既包含用户家目录敏感位置，也包含系统级敏感位置。
    private static let hardDenyPrefixesTilde: [String] = [
        "~/Library/Keychains/",
        "~/.ssh/",
        "~/Library/Cookies/",
        "/etc/",
        "/var/db/",
        "/Library/Keychains/"
    ]

    // MARK: - 实例字段（启动时一次性展开为绝对路径）

    /// 已展开 `~` 的默认读白名单（带尾随 `/`）。
    private let normalizedDefaultReadPrefixes: [String]
    /// 已展开 `~` 的默认写白名单（带尾随 `/`）。
    private let normalizedDefaultWritePrefixes: [String]
    /// 已展开 `~` 的硬禁止前缀（带尾随 `/`）。
    private let normalizedHardDenyPrefixes: [String]
    /// 用户附加白名单（已展开 `~`、补尾随 `/`）。
    /// **M2 阶段始终为空**；Phase 1 才把 Settings UI 的"File Access"用户配置注入进来。
    private let normalizedUserAllowlist: [String]

    // MARK: - 构造

    /// 构造 PathSandbox。
    ///
    /// - Parameter userAllowlist: 用户附加白名单（M2 阶段保持默认空数组即可；
    ///   Phase 1 由 Settings → Permissions → File Access 用户配置注入）。
    ///   元素允许带或不带尾随 `/`，内部统一补齐；允许带 `~`，内部统一展开。
    public init(userAllowlist: [String] = []) {
        // 在 init 阶段一次性把 ~ 展开 + 补尾随 /，避免每次 normalize 都重复字符串处理
        let expand = Self.expandTildeAndEnsureTrailingSlash
        self.normalizedDefaultReadPrefixes = Self.defaultReadAllowlistTilde.map(expand)
        self.normalizedDefaultWritePrefixes = Self.defaultWriteAllowlistTilde.map(expand)
        self.normalizedHardDenyPrefixes = Self.hardDenyPrefixesTilde.map(expand)
        self.normalizedUserAllowlist = userAllowlist.map(expand)
    }

    // MARK: - 公共 API

    /// 规范化 + 校验路径，返回安全可用的绝对 `URL`。
    ///
    /// 处理链（顺序固定，见 type-level 注释）：
    /// 1. 校验非空
    /// 2. `URL(fileURLWithPath:).resolvingSymlinksInPath().standardizedFileURL`
    /// 3. 命中硬禁止前缀 → 立即抛 `.escapesAllowlist`
    /// 4. 角色为 `.write` 且路径不在写白名单 → 抛 `.writeNotPermittedForReadOnlyPath`
    /// 5. 命中（默认 + 用户）白名单 → 返回；否则抛 `.escapesAllowlist`
    ///
    /// - Parameters:
    ///   - raw: 调用方传入的原始路径字符串；可含 `~`、相对段、`..`、symlink。
    ///   - role: 访问角色（读 / 写）。
    /// - Returns: 经过规范化（symlink 展开 + `..` 消除）的绝对 `URL`，带文件 scheme。
    /// - Throws: `PathSandboxError`，三种 case 见类型定义。
    public func normalize(_ raw: String, role: AccessRole) throws -> URL {
        // 1. 输入合法性：空串 / 全空白 / `~` 展开后仍非绝对路径都视为非法
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PathSandboxError.invalidInput(rawPath: raw)
        }

        // 2. 把 ~ 展开成绝对路径，再交给 URL(fileURLWithPath:)
        //    URL 自身不展开 ~，必须先用 NSString.expandingTildeInPath 处理
        let expanded = (trimmed as NSString).expandingTildeInPath
        // 展开后必须以 / 起头，否则不是合法绝对路径（例：传 "foo/bar" 不展开就直接拒绝）
        guard expanded.hasPrefix("/") else {
            throw PathSandboxError.invalidInput(rawPath: raw)
        }

        // 3. 规范化顺序：先 resolvingSymlinksInPath（防 symlink 跨白名单），后 standardizedFileURL（消 ..）
        //    顺序不能换：standardizedFileURL 不展开 symlink，单独用无法防"白名单目录里的恶意软链"
        let normalizedURL = URL(fileURLWithPath: expanded)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        // 4. 用 path 字符串做 hasPrefix 比较；末尾补 / 是为了精确匹配目录前缀
        //    （例：若不补 /，"/Users/foo/Doc" 也会被 "/Users/foo/Doc" 前缀通过，但这里前缀本来就是带 / 的目录）
        let normalizedPath = normalizedURL.path
        // 给规范化路径补尾随 /，确保 hasPrefix 比对时"目录"和"目录 + 同名前缀文件"不会撞车
        // （例：normalizedPath = "/Users/foo/DocumentsBackup", prefix = "/Users/foo/Documents/" → 不命中，正确）
        let pathForPrefixCompare = normalizedPath.hasSuffix("/") ? normalizedPath : normalizedPath + "/"

        // 5. 硬禁止优先生效：即使用户把 Keychains 加入 allowlist，也直接拒绝
        if Self.matchesAnyPrefix(pathForPrefixCompare, prefixes: normalizedHardDenyPrefixes) {
            throw PathSandboxError.escapesAllowlist(rawPath: raw, normalized: normalizedPath)
        }

        // 6. 角色判定
        switch role {
        case .read:
            // .read：默认读白名单 ∪ 用户白名单
            let allowed = Self.matchesAnyPrefix(pathForPrefixCompare, prefixes: normalizedDefaultReadPrefixes)
                || Self.matchesAnyPrefix(pathForPrefixCompare, prefixes: normalizedUserAllowlist)
            guard allowed else {
                throw PathSandboxError.escapesAllowlist(rawPath: raw, normalized: normalizedPath)
            }
        case .write:
            // .write：严格子集——默认写白名单 ∪ 用户白名单
            // 若路径仅在 .read 白名单（如 ~/Documents）但不在 .write 白名单 → 抛 writeNotPermittedForReadOnlyPath
            // 若路径压根不在任何白名单 → 抛 escapesAllowlist
            let inWriteAllowlist = Self.matchesAnyPrefix(pathForPrefixCompare, prefixes: normalizedDefaultWritePrefixes)
                || Self.matchesAnyPrefix(pathForPrefixCompare, prefixes: normalizedUserAllowlist)
            if !inWriteAllowlist {
                let inReadAllowlist = Self.matchesAnyPrefix(
                    pathForPrefixCompare,
                    prefixes: normalizedDefaultReadPrefixes
                )
                if inReadAllowlist {
                    // 在读白名单但不在写白名单 → 明确告诉 caller "路径合法但不可写"
                    throw PathSandboxError.writeNotPermittedForReadOnlyPath(normalized: normalizedPath)
                } else {
                    // 完全不在任何白名单 → 与 .read 同等待遇
                    throw PathSandboxError.escapesAllowlist(rawPath: raw, normalized: normalizedPath)
                }
            }
        }

        return normalizedURL
    }

    // MARK: - 私有 helper

    /// 把单个前缀字符串展开 `~` 并保证以 `/` 结尾。
    ///
    /// - Parameter prefix: 原始前缀（可能带 `~`、可能没尾随 `/`）。
    /// - Returns: 已展开 + 已补尾随 `/` 的绝对前缀。
    private static func expandTildeAndEnsureTrailingSlash(_ prefix: String) -> String {
        // NSString.expandingTildeInPath 会把 "~" / "~/foo" 展开为 "$HOME" / "$HOME/foo"
        let expanded = (prefix as NSString).expandingTildeInPath
        // 确保尾随 /，hasPrefix 才能精确按"目录"匹配，避免 ~/DocumentsBackup 误命中 ~/Documents
        return expanded.hasSuffix("/") ? expanded : expanded + "/"
    }

    /// 判断 `path` 是否命中前缀列表中的任意一个（`hasPrefix`）。
    ///
    /// - Parameters:
    ///   - path: 已带尾随 `/` 的待校验路径。
    ///   - prefixes: 已规范化（绝对 + 尾随 `/`）的前缀列表。
    /// - Returns: 命中任何一个返回 `true`；空列表恒返回 `false`。
    private static func matchesAnyPrefix(_ path: String, prefixes: [String]) -> Bool {
        // 空列表（典型：M2 用户白名单） → 直接 false，避免无谓循环
        guard !prefixes.isEmpty else { return false }
        return prefixes.contains { path.hasPrefix($0) }
    }
}
