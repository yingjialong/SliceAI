import Foundation
import OSLog
import SliceCore

/// 单个候选 skill 的加载结果。
private enum SkillCandidateLoadOutcome {
    case parsed(SkillMarkdownParseResult)
    case invalid(SkillRegistryDiagnosticCode, String, SkillRegistryState)
}

/// 文件系统 backed skill registry。
public actor LocalSkillRegistry: SkillRegistryProtocol {
    private let logger = Logger(subsystem: "com.sliceai.capabilities", category: "LocalSkillRegistry")
    private let settingsProvider: @Sendable () async -> SkillSettings
    private let scanner: SkillDirectoryScanner
    private let parser: SkillMarkdownParser

    /// 构造 LocalSkillRegistry。
    public init(
        settingsProvider: @escaping @Sendable () async -> SkillSettings,
        scanner: SkillDirectoryScanner = SkillDirectoryScanner(),
        parser: SkillMarkdownParser = SkillMarkdownParser()
    ) {
        self.settingsProvider = settingsProvider
        self.scanner = scanner
        self.parser = parser
    }

    /// 生成 registry 快照。
    public func snapshot() async throws -> SkillRegistrySnapshot {
        let settings = await settingsProvider()
        var skills: [Skill] = []
        var diagnostics: [SkillRegistryDiagnostic] = []

        for source in settings.sources.sorted(by: { $0.order < $1.order }) where source.isEnabled {
            appendSource(source, settings: settings, skills: &skills, diagnostics: &diagnostics)
        }
        applyShadowing(to: &skills, diagnostics: &diagnostics)

        logger.debug("skill registry snapshot generated count=\(skills.count, privacy: .public)")
        return SkillRegistrySnapshot(
            sources: settings.sources,
            skills: skills,
            diagnostics: diagnostics,
            generatedAt: Date()
        )
    }

    /// 查找可加载的 enabled skill。
    public func findSkill(id: String) async throws -> Skill? {
        let snapshot = try await snapshot()
        return snapshot.skills.first { $0.id == id && $0.state == .enabled }
    }

    /// 加载 enabled skill 的 SKILL.md 指令正文。
    public func loadSkillInstructions(id: String) async throws -> SkillInstructionPayload {
        guard let skill = try await findSkill(id: id) else {
            throw SliceError.configuration(.validationFailed("Skill not loadable: <redacted>"))
        }
        let data = try Data(contentsOf: skill.skillFile)
        guard data.count <= SkillMarkdownParser.maxSkillBytes else {
            throw SliceError.configuration(.validationFailed("Skill too large: <redacted>"))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SliceError.configuration(.validationFailed("Skill is not valid UTF-8: <redacted>"))
        }
        let result = try parser.parse(text, directoryName: skill.path.lastPathComponent)
        return SkillInstructionPayload(
            id: skill.id,
            canonicalName: skill.canonicalName,
            skillFile: skill.skillFile,
            frontmatterSummary: result.manifest,
            instructions: result.instructions
        )
    }

    /// 扫描并追加单个 source 的 skill 候选。
    private func appendSource(
        _ source: SkillSource,
        settings: SkillSettings,
        skills: inout [Skill],
        diagnostics: inout [SkillRegistryDiagnostic]
    ) {
        do {
            let result = try scanner.scan(in: source)
            for rejection in result.rejections {
                diagnostics.append(diagnostic(
                    code: .symlinkEscape,
                    source: source,
                    path: rejection.path,
                    message: "Skill 路径包含越界符号链接，已跳过。"
                ))
            }

            // 文件系统顺序不稳定；按路径排序让 snapshot 和测试结果可重复。
            for candidate in result.candidates.sorted(by: { $0.directory.path < $1.directory.path }) {
                skills.append(makeSkill(candidate: candidate, settings: settings, diagnostics: &diagnostics))
            }
        } catch {
            logger.warning("skill source unreadable source=\(source.id, privacy: .public)")
            diagnostics.append(diagnostic(
                code: .sourceUnreadable,
                source: source,
                path: URL(fileURLWithPath: source.rootPath, isDirectory: true),
                message: "Skill 来源目录无法读取。"
            ))
        }
    }

    /// 从 scanner 候选构造 canonical Skill。
    private func makeSkill(
        candidate: SkillCandidate,
        settings: SkillSettings,
        diagnostics: inout [SkillRegistryDiagnostic]
    ) -> Skill {
        let fallbackName = candidate.directory.lastPathComponent
        let sourceRef = SkillSourceRef(sourceId: candidate.source.id, rootPath: candidate.source.rootPath)

        switch loadCandidate(candidate, fallbackName: fallbackName) {
        case .parsed(let result):
            appendMissingDescriptionDiagnostic(for: result, candidate: candidate, diagnostics: &diagnostics)
            return parsedSkill(result: result, candidate: candidate, sourceRef: sourceRef, settings: settings)
        case .invalid(let code, let message, let state):
            diagnostics.append(diagnostic(
                code: code,
                source: candidate.source,
                path: candidate.skillFile,
                message: message
            ))
            return errorSkill(
                name: fallbackName,
                candidate: candidate,
                sourceRef: sourceRef,
                state: state
            )
        }
    }

    /// 读取并解析单个候选 `SKILL.md`。
    private func loadCandidate(_ candidate: SkillCandidate, fallbackName: String) -> SkillCandidateLoadOutcome {
        do {
            let data = try Data(contentsOf: candidate.skillFile)
            guard data.count <= SkillMarkdownParser.maxSkillBytes else {
                return .invalid(.tooLarge, "SKILL.md 超过 128KiB，已禁用。", .tooLarge)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return .invalid(.parseError, "SKILL.md 不是有效 UTF-8。", .parseError)
            }
            return .parsed(try parser.parse(text, directoryName: fallbackName))
        } catch {
            logger.warning("skill parse failed source=\(candidate.source.id, privacy: .public)")
            return .invalid(.parseError, "SKILL.md 解析失败。", .parseError)
        }
    }

    /// 在缺少 description 时追加默认禁用诊断。
    private func appendMissingDescriptionDiagnostic(
        for result: SkillMarkdownParseResult,
        candidate: SkillCandidate,
        diagnostics: inout [SkillRegistryDiagnostic]
    ) {
        guard result.warnings.contains(.missingDescription) else { return }
        diagnostics.append(diagnostic(
            code: .missingDescription,
            source: candidate.source,
            path: candidate.skillFile,
            message: "SKILL.md 缺少 description，默认禁用。"
        ))
    }

    /// 从已解析结果构造可用 skill。
    private func parsedSkill(
        result: SkillMarkdownParseResult,
        candidate: SkillCandidate,
        sourceRef: SkillSourceRef,
        settings: SkillSettings
    ) -> Skill {
        Skill(
            id: result.manifest.name,
            canonicalName: result.manifest.name,
            path: candidate.directory,
            skillFile: candidate.skillFile,
            manifest: result.manifest,
            resources: indexedResources(in: candidate.directory),
            provenance: .selfManaged(userAcknowledgedAt: Date()),
            source: sourceRef,
            state: state(for: result, settings: settings)
        )
    }

    /// 根据 frontmatter、warning 与用户 override 计算 registry state。
    private func state(for result: SkillMarkdownParseResult, settings: SkillSettings) -> SkillRegistryState {
        let override = settings.overrides[result.manifest.name]
        if override == .off {
            return .disabled
        }
        if result.warnings.contains(.missingDescription), override != .on {
            return .defaultDisabled
        }
        if result.manifest.disableModelInvocation, override != .on {
            return .defaultDisabled
        }
        return .enabled
    }

    /// 对 enabled duplicate 做 shadowing，保留 source order 中第一个 enabled skill。
    private func applyShadowing(to skills: inout [Skill], diagnostics: inout [SkillRegistryDiagnostic]) {
        var activeNames: Set<String> = []
        for index in skills.indices where skills[index].state == .enabled {
            let name = skills[index].canonicalName
            if activeNames.contains(name) {
                skills[index].state = .shadowed
                diagnostics.append(SkillRegistryDiagnostic(
                    code: .duplicateName,
                    sourceId: skills[index].source.sourceId,
                    path: skills[index].skillFile.path,
                    message: "Skill 名称重复，较低优先级版本已隐藏。"
                ))
            } else {
                activeNames.insert(name)
            }
        }
    }

    /// 构造错误状态下仍可展示的 skill。
    private func errorSkill(
        name: String,
        candidate: SkillCandidate,
        sourceRef: SkillSourceRef,
        state: SkillRegistryState
    ) -> Skill {
        Skill(
            id: name,
            canonicalName: name,
            path: candidate.directory,
            skillFile: candidate.skillFile,
            manifest: SkillManifest(name: name, description: ""),
            resources: [],
            provenance: .selfManaged(userAcknowledgedAt: Date()),
            source: sourceRef,
            state: state
        )
    }

    /// 构造短 UI 诊断。
    private func diagnostic(
        code: SkillRegistryDiagnosticCode,
        source: SkillSource,
        path: URL,
        message: String
    ) -> SkillRegistryDiagnostic {
        SkillRegistryDiagnostic(
            code: code,
            sourceId: source.id,
            path: path.path,
            message: message
        )
    }
}

extension LocalSkillRegistry {
    /// 单个 supporting file 进入模型上下文前的最大字节数。
    private static var maxResourceBytes: Int { 64 * 1024 }

    /// 加载 enabled skill 内已索引 supporting file 的 UTF-8 文本。
    public func loadSkillResource(id: String, relativePath: String) async throws -> SkillResourcePayload {
        guard let skill = try await findSkill(id: id) else {
            throw SliceError.configuration(.validationFailed("Skill resource not loadable: <redacted>"))
        }
        let normalizedPath = try normalizedResourcePath(relativePath)
        guard let resource = skill.resources.first(where: { $0.relativePath == normalizedPath }) else {
            throw SliceError.configuration(.validationFailed("Skill resource not indexed: <redacted>"))
        }
        let fileURL = skill.path.appendingPathComponent(normalizedPath, isDirectory: false).standardizedFileURL
        let content = try readResourceContent(fileURL: fileURL, skillRoot: skill.path)
        logger.debug("loaded SliceAI skill resource \(normalizedPath, privacy: .public)")
        return SkillResourcePayload(
            id: skill.id,
            canonicalName: skill.canonicalName,
            relativePath: normalizedPath,
            fileURL: fileURL,
            mimeType: resource.mimeType,
            content: content
        )
    }

    /// 执行 supporting file 的安全读取。
    private func readResourceContent(fileURL: URL, skillRoot: URL) throws -> String {
        let resolvedFileURL = fileURL.resolvingSymlinksInPath()
        guard isPath(resolvedFileURL, inside: skillRoot.resolvingSymlinksInPath()) else {
            throw SliceError.configuration(.validationFailed("Skill resource escaped root: <redacted>"))
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: resolvedFileURL.path)
        if let fileSize = attributes[.size] as? NSNumber,
           fileSize.intValue > Self.maxResourceBytes {
            throw SliceError.configuration(.validationFailed("Skill resource too large: <redacted>"))
        }
        let data = try Data(contentsOf: resolvedFileURL)
        guard data.count <= Self.maxResourceBytes else {
            throw SliceError.configuration(.validationFailed("Skill resource too large: <redacted>"))
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw SliceError.configuration(.validationFailed("Skill resource is not valid UTF-8: <redacted>"))
        }
        return content
    }
}

/// 常见 UTF-8 文本 supporting file 扩展名到 MIME 类型的映射。
private let skillTextResourceMIMETypes: [String: String] = [
    "bash": "text/x-shellscript",
    "c": "text/x-c",
    "cpp": "text/x-c++",
    "css": "text/css",
    "csv": "text/csv",
    "html": "text/html",
    "htm": "text/html",
    "ini": "text/plain",
    "js": "text/javascript",
    "json": "application/json",
    "md": "text/markdown",
    "markdown": "text/markdown",
    "mjs": "text/javascript",
    "py": "text/x-python",
    "rb": "text/x-ruby",
    "rst": "text/x-rst",
    "sh": "text/x-shellscript",
    "swift": "text/x-swift",
    "toml": "application/toml",
    "ts": "text/typescript",
    "tsx": "text/typescript",
    "txt": "text/plain",
    "xml": "application/xml",
    "yaml": "application/yaml",
    "yml": "application/yaml",
    "zsh": "text/x-shellscript"
]

/// 扫描 skill 目录中可读 supporting files。
/// - Parameter skillDirectory: 单个 skill 根目录。
/// - Returns: 可暴露给 Agent 的只读资源索引。
private func indexedResources(in skillDirectory: URL) -> [SkillResource] {
    let roots = [
        skillDirectory.appendingPathComponent("references", isDirectory: true),
        skillDirectory.appendingPathComponent("assets", isDirectory: true)
    ]
    let resolvedSkillRoot = skillDirectory.resolvingSymlinksInPath()
    var resources: [SkillResource] = []

    for root in roots {
        resources.append(contentsOf: indexedResources(
            in: root,
            skillDirectory: skillDirectory,
            resolvedRoot: resolvedSkillRoot
        ))
    }
    return resources.sorted { $0.relativePath < $1.relativePath }
}

/// 扫描一个 supporting file 子目录。
private func indexedResources(in root: URL, skillDirectory: URL, resolvedRoot: URL) -> [SkillResource] {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return []
    }
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
        return []
    }

    var resources: [SkillResource] = []
    for case let fileURL as URL in enumerator {
        guard let resource = indexedResource(
            fileURL,
            skillDirectory: skillDirectory,
            resolvedRoot: resolvedRoot
        ) else {
            continue
        }
        resources.append(resource)
    }
    return resources
}

/// 将单个文件转为 SkillResource；不满足只读安全边界时返回 nil。
private func indexedResource(_ fileURL: URL, skillDirectory: URL, resolvedRoot: URL) -> SkillResource? {
    guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
          values.isRegularFile == true else {
        return nil
    }
    let resolvedURL = fileURL.resolvingSymlinksInPath()
    guard isPath(resolvedURL, inside: resolvedRoot) else {
        return nil
    }
    let fileExtension = fileURL.pathExtension.lowercased()
    guard let mimeType = skillTextResourceMIMETypes[fileExtension],
          let relativePath = relativePath(from: skillDirectory, to: fileURL),
          isLoadableResourcePath(relativePath) else {
        return nil
    }
    return SkillResource(relativePath: relativePath, mimeType: mimeType)
}

/// 标准化并校验模型请求的 resource 相对路径。
private func normalizedResourcePath(_ relativePath: String) throws -> String {
    guard !relativePath.isEmpty,
          !relativePath.hasPrefix("/"),
          !relativePath.contains("\\"),
          !relativePath.contains("\0") else {
        throw SliceError.configuration(.validationFailed("Invalid skill resource path: <redacted>"))
    }
    let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !parts.contains(""),
          !parts.contains("."),
          !parts.contains(".."),
          isLoadableResourcePath(relativePath) else {
        throw SliceError.configuration(.validationFailed("Invalid skill resource path: <redacted>"))
    }
    return parts.joined(separator: "/")
}

/// 判断相对路径是否属于本切片允许读取的 supporting file 范围。
private func isLoadableResourcePath(_ relativePath: String) -> Bool {
    relativePath.hasPrefix("references/") || relativePath.hasPrefix("assets/")
}

/// 计算 file 相对 skill 根目录的稳定 POSIX 风格路径。
private func relativePath(from root: URL, to file: URL) -> String? {
    let rootComponents = root.standardizedFileURL.pathComponents
    let fileComponents = file.standardizedFileURL.pathComponents
    guard fileComponents.count > rootComponents.count,
          Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
        return nil
    }
    return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
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
