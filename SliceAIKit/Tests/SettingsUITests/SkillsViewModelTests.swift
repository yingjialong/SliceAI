import Capabilities
import Foundation
import SliceCore
@testable import SettingsUI
import XCTest

/// Skills 设置页视图模型行为测试。
@MainActor
final class SkillsViewModelTests: XCTestCase {

    /// 添加、移动、删除 source 应写入 SettingsViewModel 的配置并持久化到 store。
    func test_sourceMutationsPersistToConfiguration() async throws {
        let store = ConfigurationStore(fileURL: try makeTemporaryFileURL(), legacyFileURL: nil)
        let settingsViewModel = SettingsViewModel(
            store: store,
            keychain: SettingsUITestKeychain(),
            skillRegistry: StaticSkillRegistry(skills: [])
        )
        await settingsViewModel.reload()
        let viewModel = SkillsViewModel(
            settingsViewModel: settingsViewModel,
            skillRegistry: StaticSkillRegistry(skills: [])
        )

        await viewModel.addSource(path: "/tmp/sliceai-skills-a")
        await viewModel.addSource(path: "/tmp/sliceai-skills-b")
        let secondID = try XCTUnwrap(settingsViewModel.configuration.skillSettings.sources.last?.id)

        await viewModel.moveSource(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        await viewModel.removeSource(id: secondID)

        let loaded = try await store.current()
        XCTAssertEqual(loaded.skillSettings.sources.map(\.rootPath), ["/tmp/sliceai-skills-a"])
        XCTAssertEqual(loaded.skillSettings.sources.map(\.order), [0])
    }

    /// Override 应保存到配置，并在 VM 快照中覆盖 registry 原始 enabled 状态。
    func test_setOverridePersistsAndAppliesToSnapshot() async throws {
        let skill = makeSkill(id: "writing", state: .enabled)
        let store = ConfigurationStore(fileURL: try makeTemporaryFileURL(), legacyFileURL: nil)
        let registry = StaticSkillRegistry(skills: [skill])
        let settingsViewModel = SettingsViewModel(
            store: store,
            keychain: SettingsUITestKeychain(),
            skillRegistry: registry
        )
        await settingsViewModel.reload()
        let viewModel = SkillsViewModel(settingsViewModel: settingsViewModel, skillRegistry: registry)

        await viewModel.reload()
        await viewModel.setOverride(.off, for: skill.id)

        let loaded = try await store.current()
        XCTAssertEqual(loaded.skillSettings.overrides[skill.id], .off)
        XCTAssertEqual(viewModel.skills.first?.state, .disabled)

        await viewModel.setOverride(nil, for: skill.id)

        XCTAssertNil(settingsViewModel.configuration.skillSettings.overrides[skill.id])
        XCTAssertEqual(viewModel.skills.first?.state, .enabled)
    }

    /// 创建测试用临时 config-v2.json 路径。
    /// - Returns: 位于临时目录下的配置文件 URL。
    private func makeTemporaryFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("config-v2.json")
    }

    /// 构造最小 Skill fixture。
    /// - Parameters:
    ///   - id: skill id。
    ///   - state: registry state。
    /// - Returns: 可用于设置页测试的 Skill。
    private func makeSkill(id: String, state: SkillRegistryState) -> Skill {
        Skill(
            id: id,
            canonicalName: id,
            path: URL(fileURLWithPath: "/tmp/\(id)"),
            skillFile: URL(fileURLWithPath: "/tmp/\(id)/SKILL.md"),
            manifest: SkillManifest(name: id, description: "Test skill \(id)"),
            resources: [],
            provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 0)),
            source: SkillSourceRef(sourceId: "test", rootPath: "/tmp"),
            state: state
        )
    }
}

/// SettingsUITests 内存 Keychain。
private final actor SettingsUITestKeychain: KeychainAccessing {

    /// 内存 API Key 字典。
    private var values: [String: String] = [:]

    /// 读取测试 API Key。
    /// - Parameter providerId: Provider keychain account。
    /// - Returns: 已保存值或 nil。
    func readAPIKey(providerId: String) async throws -> String? {
        values[providerId]
    }

    /// 写入测试 API Key。
    /// - Parameters:
    ///   - value: API Key。
    ///   - providerId: Provider keychain account。
    func writeAPIKey(_ value: String, providerId: String) async throws {
        values[providerId] = value
    }

    /// 删除测试 API Key。
    /// - Parameter providerId: Provider keychain account。
    func deleteAPIKey(providerId: String) async throws {
        values.removeValue(forKey: providerId)
    }
}

/// 固定快照 SkillRegistry，避免测试依赖文件扫描。
private actor StaticSkillRegistry: SkillRegistryProtocol {

    /// 固定返回的 skills。
    private let skills: [Skill]

    /// 构造固定 registry。
    /// - Parameter skills: snapshot 中返回的 skills。
    init(skills: [Skill]) {
        self.skills = skills
    }

    /// 返回固定 snapshot。
    /// - Returns: 测试 snapshot。
    func snapshot() async throws -> SkillRegistrySnapshot {
        SkillRegistrySnapshot(sources: [], skills: skills, diagnostics: [], generatedAt: Date())
    }

    /// 查找 enabled skill。
    /// - Parameter id: skill id。
    /// - Returns: enabled skill 或 nil。
    func findSkill(id: String) async throws -> Skill? {
        skills.first { $0.id == id && $0.state == .enabled }
    }

    /// 测试不覆盖正文加载。
    /// - Parameter id: skill id。
    /// - Returns: 不会返回。
    func loadSkillInstructions(id: String) async throws -> SkillInstructionPayload {
        throw SliceError.configuration(.validationFailed("not implemented in SettingsUITests"))
    }
}
