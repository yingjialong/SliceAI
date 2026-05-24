import Foundation
import os
import SliceCore

private let skillDirectoryScannerLog = Logger(
    subsystem: "com.sliceai.capabilities",
    category: "SkillDirectoryScanner"
)

/// 从用户配置的 root 中发现 `SKILL.md` 候选文件。
public struct SkillDirectoryScanner: Sendable {
    public static let maxCandidatesPerSource = 200

    /// 构造 skill 目录扫描器。
    public init() {}

    /// 发现一个 source root 下的候选 skill。
    /// - Parameter source: 用户配置的 skill root。
    /// - Returns: 已通过安全检查的候选 skill。
    /// - Throws: 目录枚举失败时透传 `FileManager` 错误。
    public func candidates(in source: SkillSource) throws -> [SkillCandidate] {
        try scan(in: source).candidates
    }

    /// 发现候选 skill，并返回被安全规则拒绝的路径摘要。
    /// - Parameter source: 用户配置的 skill root。
    /// - Returns: 候选 skill 与拒绝记录。
    /// - Throws: 目录枚举失败时透传 `FileManager` 错误。
    public func scan(in source: SkillSource) throws -> SkillDirectoryScanResult {
        guard source.isEnabled else {
            skillDirectoryScannerLog.debug("Skip disabled skill source: \(source.id, privacy: .public)")
            return SkillDirectoryScanResult(candidates: [], rejections: [])
        }

        let root = try resolvedRoot(for: source)
        var builder = SkillDirectoryScanBuilder(source: source, resolvedRoot: root.resolvedURL)
        appendRootSkillIfPresent(root: root.url, builder: &builder)
        try appendChildSkillCandidates(root: root.url, builder: &builder)

        skillDirectoryScannerLog.debug(
            """
            Scanned skill source \(source.id, privacy: .public): \
            candidates=\(builder.candidateCount), rejections=\(builder.rejectionCount)
            """
        )
        return builder.result(maxCandidates: Self.maxCandidatesPerSource)
    }
}

/// Scanner 结果；registry 将 rejections 映射为 UI diagnostics。
public struct SkillDirectoryScanResult: Sendable, Equatable {
    public let candidates: [SkillCandidate]
    public let rejections: [SkillDirectoryScannerRejection]

    /// 构造 scanner 结果。
    public init(candidates: [SkillCandidate], rejections: [SkillDirectoryScannerRejection]) {
        self.candidates = candidates
        self.rejections = rejections
    }
}

/// Scanner 发现的候选 skill 目录。
public struct SkillCandidate: Sendable, Equatable {
    public let source: SkillSource
    public let directory: URL
    public let skillFile: URL

    /// 构造候选 skill。
    public init(source: SkillSource, directory: URL, skillFile: URL) {
        self.source = source
        self.directory = directory
        self.skillFile = skillFile
    }
}

/// Scanner 拒绝候选的原因摘要。
public struct SkillDirectoryScannerRejection: Sendable, Equatable {
    public let source: SkillSource
    public let path: URL
    public let reason: SkillDirectoryScannerRejectionReason

    /// 构造拒绝记录。
    public init(source: SkillSource, path: URL, reason: SkillDirectoryScannerRejectionReason) {
        self.source = source
        self.path = path
        self.reason = reason
    }
}

/// Scanner 拒绝候选的原因。
public enum SkillDirectoryScannerRejectionReason: Sendable, Equatable {
    case symlinkEscapesSourceRoot
}

/// Scanner 发现 source root 无法作为目录读取。
public enum SkillDirectoryScannerError: Error, Sendable, Equatable {
    case sourceRootUnreadable
}

/// 返回本 MVP 支持的一层扫描父目录。
private func candidateParentDirectories(root: URL) -> [URL] {
    [
        root,
        root.appendingPathComponent("skills", isDirectory: true),
        root.appendingPathComponent(".claude/skills", isDirectory: true),
        root.appendingPathComponent(".agents/skills", isDirectory: true),
        root.appendingPathComponent(".codex/skills", isDirectory: true)
    ]
}

/// 标准化后的 source root。
private struct ResolvedSkillSourceRoot {
    let url: URL
    let resolvedURL: URL
}

/// 单次 source 扫描的累加器。
private struct SkillDirectoryScanBuilder {
    let source: SkillSource
    let resolvedRoot: URL
    private var candidates: [SkillCandidate] = []
    private var rejections: [SkillDirectoryScannerRejection] = []

    /// 构造 source 扫描累加器。
    init(source: SkillSource, resolvedRoot: URL) {
        self.source = source
        self.resolvedRoot = resolvedRoot
    }

    /// 当前候选数量，用于诊断日志。
    var candidateCount: Int { candidates.count }

    /// 当前拒绝数量，用于诊断日志。
    var rejectionCount: Int { rejections.count }

    /// 在安全检查通过时追加候选，否则记录拒绝原因。
    mutating func appendCandidateIfAllowed(directory: URL, skillFile: URL) {
        let resolvedDirectory = directory.resolvingSymlinksInPath()
        let resolvedSkillFile = skillFile.resolvingSymlinksInPath()
        guard isPath(resolvedDirectory, inside: resolvedRoot),
              isPath(resolvedSkillFile, inside: resolvedRoot) else {
            let sourceID = source.id
            skillDirectoryScannerLog.warning(
                "Rejected skill candidate escaping source root source=\(sourceID, privacy: .public)"
            )
            rejections.append(
                SkillDirectoryScannerRejection(
                    source: source,
                    path: directory,
                    reason: .symlinkEscapesSourceRoot
                )
            )
            return
        }

        candidates.append(
            SkillCandidate(
                source: source,
                directory: directory.standardizedFileURL,
                skillFile: skillFile.standardizedFileURL
            )
        )
    }

    /// 输出 scanner 结果，并应用每个 source 的候选数量上限。
    func result(maxCandidates: Int) -> SkillDirectoryScanResult {
        SkillDirectoryScanResult(
            candidates: Array(candidates.prefix(maxCandidates)),
            rejections: rejections
        )
    }
}

/// 解析并校验 source root。
private func resolvedRoot(for source: SkillSource) throws -> ResolvedSkillSourceRoot {
    let root = URL(fileURLWithPath: source.rootPath, isDirectory: true).standardizedFileURL
    var isRootDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isRootDirectory),
          isRootDirectory.boolValue else {
        throw SkillDirectoryScannerError.sourceRootUnreadable
    }
    return ResolvedSkillSourceRoot(url: root, resolvedURL: root.resolvingSymlinksInPath())
}

/// 如果 source root 自身包含 `SKILL.md`，追加为候选。
private func appendRootSkillIfPresent(root: URL, builder: inout SkillDirectoryScanBuilder) {
    let skillFile = root.appendingPathComponent("SKILL.md", isDirectory: false)
    guard FileManager.default.fileExists(atPath: skillFile.path) else { return }
    builder.appendCandidateIfAllowed(directory: root, skillFile: skillFile)
}

/// 扫描各个支持的父目录，并追加一层子 skill 候选。
private func appendChildSkillCandidates(root: URL, builder: inout SkillDirectoryScanBuilder) throws {
    for parent in candidateParentDirectories(root: root) {
        let children = try directChildrenWithSkillFiles(parent: parent)
        for child in children {
            builder.appendCandidateIfAllowed(directory: child.directory, skillFile: child.skillFile)
        }
    }
}

/// 枚举 parent 的直接子目录，并筛选包含 `SKILL.md` 的目录。
private func directChildrenWithSkillFiles(parent: URL) throws -> [(directory: URL, skillFile: URL)] {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return []
    }

    let children = try FileManager.default.contentsOfDirectory(
        at: parent,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsPackageDescendants]
    )

    return children.compactMap { child in
        // 这里只检查直接子目录下的 SKILL.md，明确不递归扫描更深层级。
        let skillFile = child.appendingPathComponent("SKILL.md", isDirectory: false)
        guard FileManager.default.fileExists(atPath: skillFile.path) else {
            return nil
        }
        return (directory: child.standardizedFileURL, skillFile: skillFile.standardizedFileURL)
    }
}

/// 使用 pathComponents 判断包含关系，避免 `/tmp/root2` 被误判为 `/tmp/root` 子路径。
private func isPath(_ child: URL, inside root: URL) -> Bool {
    let childComponents = child.standardizedFileURL.pathComponents
    let rootComponents = root.standardizedFileURL.pathComponents
    guard childComponents.count >= rootComponents.count else {
        return false
    }
    return Array(childComponents.prefix(rootComponents.count)) == rootComponents
}
