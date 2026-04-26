import Foundation
import SliceCore

/// 测试用假 Keychain：内存字典存储，预置 key 通过 init 传入
///
/// 用 `actor` 保证 read/write/delete 在并发测试场景下线程安全（KeychainAccessing 协议本身要求 Sendable）。
/// 与 SliceCoreTests/ToolExecutorTests.swift 中的 private FakeKeychain 形态保持一致，便于跨文件复用心智模型。
final actor MockKeychain: KeychainAccessing {

    /// 内部存储：providerId → API Key 字符串
    private var store: [String: String]

    /// 构造 MockKeychain
    /// - Parameter store: 预置 key-value 表；不传默认空
    init(_ store: [String: String] = [:]) {
        self.store = store
    }

    /// 读取 API Key；不存在返回 nil
    /// - Parameter providerId: 调用方按 `Provider.keychainAccount` 解析得到的 account 名
    /// - Returns: 存在则返回字符串，否则 nil（注意"空字符串"也算存在，由 PromptExecutor 自行视作未授权）
    func readAPIKey(providerId: String) async throws -> String? {
        // 打印调试日志，便于失败测试快速定位 key 名拼写不一致问题
        print("[MockKeychain] readAPIKey providerId=\(providerId) → exists=\(store[providerId] != nil)")
        return store[providerId]
    }

    /// 写入或覆盖 API Key
    func writeAPIKey(_ value: String, providerId: String) async throws {
        store[providerId] = value
    }

    /// 删除 API Key（不存在则 no-op）
    func deleteAPIKey(providerId: String) async throws {
        store.removeValue(forKey: providerId)
    }
}
