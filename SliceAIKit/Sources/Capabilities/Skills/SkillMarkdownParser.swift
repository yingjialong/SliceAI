import Foundation
import SliceCore

/// 解析 Claude / Codex 风格 `SKILL.md` 的最小 frontmatter 子集。
public struct SkillMarkdownParser: Sendable {
    public static let maxSkillBytes = 128 * 1024

    /// 构造 `SKILL.md` 解析器。
    public init() {}

    /// 解析 `SKILL.md` 文本，返回 manifest、正文和可恢复 warning。
    /// - Parameters:
    ///   - text: `SKILL.md` 完整文本。
    ///   - directoryName: `name` 缺失或为空时使用的目录名。
    /// - Returns: 解析后的 manifest 与正文。
    /// - Throws: frontmatter 布尔字段不合法时抛出错误。
    public func parse(_ text: String, directoryName: String) throws -> SkillMarkdownParseResult {
        let parts = try splitFrontmatter(text)
        let fields = parseFields(parts.frontmatter)
        let name = fields.scalars["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = fields.scalars["description"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var warnings: Set<SkillMarkdownWarning> = []
        if description.isEmpty {
            warnings.insert(.missingDescription)
        }

        let disableModelInvocation = try parseBool(
            fields.scalars["disable-model-invocation"] ?? "false",
            fieldName: "disable-model-invocation"
        )
        let userInvocable = try fields.scalars["user-invocable"].map {
            try parseBool($0, fieldName: "user-invocable")
        }
        let manifest = SkillManifest(
            name: name?.isEmpty == false ? name ?? directoryName : directoryName,
            description: description,
            disableModelInvocation: disableModelInvocation,
            allowedTools: allowedTools(from: fields),
            userInvocable: userInvocable,
            rawFrontmatter: parts.frontmatter,
            instructionsCharacterCount: parts.body.count
        )

        return SkillMarkdownParseResult(manifest: manifest, instructions: parts.body, warnings: warnings)
    }
}

/// `SKILL.md` 解析结果。
public struct SkillMarkdownParseResult: Sendable, Equatable {
    public let manifest: SkillManifest
    public let instructions: String
    public let warnings: Set<SkillMarkdownWarning>

    /// 构造 `SKILL.md` 解析结果。
    public init(manifest: SkillManifest, instructions: String, warnings: Set<SkillMarkdownWarning>) {
        self.manifest = manifest
        self.instructions = instructions
        self.warnings = warnings
    }
}

/// `SKILL.md` 可恢复解析警告；上层 registry 决定如何展示。
public enum SkillMarkdownWarning: String, Sendable, Codable, Equatable {
    case missingDescription
}

/// `SKILL.md` 不可恢复解析错误。
public enum SkillMarkdownParserError: Error, Equatable {
    case invalidBoolean(field: String, value: String)
    case missingClosingFrontmatter
}

private struct FrontmatterParts {
    let frontmatter: String
    let body: String
}

private struct ParsedFields {
    var scalars: [String: String] = [:]
    var lists: [String: [String]] = [:]
}

/// 拆分 frontmatter 与正文；没有 frontmatter 时把全文视作正文。
private func splitFrontmatter(_ text: String) throws -> FrontmatterParts {
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
    guard normalized.hasPrefix("---\n") || normalized == "---" else {
        return FrontmatterParts(frontmatter: "", body: text)
    }

    let lines = normalized.components(separatedBy: "\n")
    guard lines.first == "---" else {
        return FrontmatterParts(frontmatter: "", body: text)
    }

    for index in lines.indices.dropFirst() where lines[index].trimmingCharacters(in: .whitespaces) == "---" {
        let frontmatter = lines[1..<index].joined(separator: "\n")
        let bodyStart = lines.index(after: index)
        let body = bodyStart < lines.endIndex ? lines[bodyStart...].joined(separator: "\n") : ""
        return FrontmatterParts(frontmatter: frontmatter, body: body)
    }

    throw SkillMarkdownParserError.missingClosingFrontmatter
}

/// 解析最小 YAML 子集：`key: value` 标量和 `key:` 后接 `- item` 列表。
private func parseFields(_ frontmatter: String) -> ParsedFields {
    var fields = ParsedFields()
    var currentListKey: String?

    for rawLine in frontmatter.components(separatedBy: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }

        if line.hasPrefix("- "), let key = currentListKey {
            // YAML 列表只支持一层，足够兼容 Claude / Codex skill manifest 的 allowed-tools。
            let item = stripQuotes(String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines))
            if !item.isEmpty {
                fields.lists[key, default: []].append(item)
            }
            continue
        }

        currentListKey = nil
        guard let colonIndex = line.firstIndex(of: ":") else { continue }
        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let valueStart = line.index(after: colonIndex)
        let value = stripQuotes(String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines))

        if value.isEmpty {
            currentListKey = key
            fields.lists[key] = fields.lists[key] ?? []
        } else {
            fields.scalars[key] = value
        }
    }

    return fields
}

/// 解析严格布尔值，避免 `yes` / `maybe` 等 YAML 宽松值被误判。
private func parseBool(_ value: String, fieldName: String) throws -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalized {
    case "true":
        return true
    case "false":
        return false
    default:
        throw SkillMarkdownParserError.invalidBoolean(field: fieldName, value: value)
    }
}

/// 解析 allowed-tools；列表优先，标量兼容为单项列表。
private func allowedTools(from fields: ParsedFields) -> [String] {
    if let tools = fields.lists["allowed-tools"] {
        return tools
    }
    guard let scalar = fields.scalars["allowed-tools"], !scalar.isEmpty else {
        return []
    }
    return [scalar]
}

/// 去掉最外层成对引号，保留内部内容。
private func stripQuotes(_ value: String) -> String {
    guard value.count >= 2 else { return value }
    if value.hasPrefix("\""), value.hasSuffix("\"") {
        return String(value.dropFirst().dropLast())
    }
    if value.hasPrefix("'"), value.hasSuffix("'") {
        return String(value.dropFirst().dropLast())
    }
    return value
}
