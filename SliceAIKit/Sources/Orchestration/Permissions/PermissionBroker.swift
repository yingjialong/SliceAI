import Foundation
import SliceCore

// MARK: - Permission tier 枚举（broker 内部使用）

/// 5 档能力分级（spec §3.9.2）
///
/// 仅在 `PermissionBroker` 内部使用——SliceCore `Permission` 11 case 不直接区分 tier，
/// 而是由 broker 内的 `inferTier(_:)` helper 做集中映射。这样 spec 表格与代码 1:1 对应，
/// 也便于 M3+ 当 SliceCore `Permission` 加 case 关联值（如 `.network(host:method:)`）后
/// 一处修改 inferTier 即可下放精度。
internal enum PermissionTier: Sendable {
    /// 读本地：clipboard 读 / fileRead / memoryAccess 读 / clipboardHistory / screen
    case readonlyLocal
    /// 读网络：HTTPS GET（M2 当前所有 .network 都归 networkWrite，本 case 留给 M3+ 细分时使用）
    case readonlyNetwork
    /// 写本地：fileWrite / clipboard 写 / replace / systemAudio
    case localWrite
    /// 写网络：POST/PUT/DELETE / MCP 写 tool
    case networkWrite
    /// 执行子进程 / AppIntents
    case exec
}

// MARK: - PermissionBroker（默认实现）

/// PermissionBroker 默认实现——按 spec §3.9.2 下限矩阵 + §3.9.1 Provenance UX hint 表做决策
///
/// **核心约束（D-22 + D-25）**：
/// - lowerBound 仅依赖 tier，与 provenance **完全无关**——provenance 只决定 UX hint 文案
/// - dry-run 不豁免下限：readonly-* / local-write 仍走完整 gate；只有 network-write / exec
///   才返回 `.wouldRequireConsent` 占位
/// - short-circuit：对 `effective` set 中第一个非 `.approved` permission 即返回，避免 UI 风暴
///
/// **测试覆盖**：`PermissionBrokerTests` 5 tier × 4 provenance = 20 cell 全覆盖（不抽样）+
/// dry-run 路径 + grant store 命中。
public actor PermissionBroker: PermissionBrokerProtocol {

    // MARK: - Stored

    /// In-memory grant 缓存（actor 隔离）
    private let store: PermissionGrantStore

    // MARK: - Init

    /// 构造默认 broker
    /// - Parameter store: in-memory grant store；默认新建空实例（生产路径同样默认空——
    ///   session-scoped grant 在用户首次确认后写入；persistent grant 留到 Phase 1 接磁盘）
    public init(store: PermissionGrantStore = .init()) {
        self.store = store
    }

    // MARK: - PermissionBrokerProtocol

    /// 对 effective 集合做 short-circuit gate；具体语义见 protocol 注释
    public func gate(
        effective: Set<Permission>,
        provenance: Provenance,
        scope: GrantScope,
        isDryRun: Bool
    ) async -> GateOutcome {
        // 中文调试日志：进入 gate（permission count + dry-run 标记），便于后续追排
        // 短路语义：第一条非 approved 的 permission 即返回，让 caller 的 UI 一次只处理一条
        // 排序遍历：Set 顺序非确定性，sort 后保证测试 / 调试可重现
        let ordered = effective.sorted(by: Self.permissionOrdering)

        for permission in ordered {
            let tier = Self.inferTier(permission)
            let outcome = await decide(
                permission: permission,
                tier: tier,
                provenance: provenance,
                scope: scope,
                isDryRun: isDryRun
            )
            switch outcome {
            case .approved:
                continue
            case .denied, .requiresUserConsent, .wouldRequireConsent:
                // 短路：返回首个非 approved 决策；调用方根据 case 决定后续动作
                return outcome
            }
        }
        // 全部 approved 才整体放行
        return .approved
    }

    // MARK: - 私有决策 helper（按 §3.9.2 + §3.9.1 表）

    /// 单个 permission 的决策；可缓存命中直接 .approved，否则按 tier × provenance × dry-run 走表
    /// - Parameters:
    ///   - permission: 待决策的 permission
    ///   - tier: 已映射好的 5 档 tier
    ///   - provenance: 工具来源
    ///   - scope: caller 建议的 grant 时长（仅用于写入 grant store；不影响下限）
    ///   - isDryRun: dry-run 标记
    /// - Returns: 单条 GateOutcome
    private func decide(
        permission: Permission,
        tier: PermissionTier,
        provenance: Provenance,
        scope: GrantScope,
        isDryRun: Bool
    ) async -> GateOutcome {
        // 1. 命中已有 grant → .approved（仅对 first-time-confirm tier 有效；each-time tier 不缓存）
        //    network-write / exec 永不缓存，直接走"每次确认"分支，不查 store
        if Self.cacheable(tier: tier) {
            let hit = await store.has(permission: permission, provenance: provenance)
            if hit {
                return .approved
            }
        }

        // 2. 按 tier 走 §3.9.2 下限决策（与 provenance 无关）
        switch tier {
        case .readonlyLocal:
            return decideReadonlyLocal(permission: permission, provenance: provenance)

        case .readonlyNetwork, .localWrite:
            // 首次确认：所有 4 provenance 都需要确认（unknown 实际上每次确认，但 M2 实现仍走 requiresUserConsent
            // 一次返回；M3+ "记住" 选项只对 firstParty/signed 显示，由 UI 层判断 provenance）
            return .requiresUserConsent(
                permission: permission,
                uxHint: Self.uxHint(tier: tier, provenance: provenance)
            )

        case .networkWrite, .exec:
            // 每次确认：dry-run 替换为 wouldRequireConsent；非 dry-run 走 requiresUserConsent
            let hint = Self.uxHint(tier: tier, provenance: provenance)
            if isDryRun {
                return .wouldRequireConsent(permission: permission, uxHint: hint)
            } else {
                return .requiresUserConsent(permission: permission, uxHint: hint)
            }
        }
    }

    /// readonly-local 的 provenance 分支（spec §3.9.1 表 line 939）：
    /// firstParty / communitySigned / selfManaged → 静默 .approved；unknown → 首次确认
    private func decideReadonlyLocal(permission: Permission, provenance: Provenance) -> GateOutcome {
        switch provenance {
        case .firstParty, .communitySigned, .selfManaged:
            return .approved
        case .unknown:
            // unknown 来源 readonly-local 仍要首次确认（spec §3.9.1 优先级高于 plan line 1718 简化表述）
            return .requiresUserConsent(
                permission: permission,
                uxHint: Self.uxHint(tier: .readonlyLocal, provenance: provenance)
            )
        }
    }

    // MARK: - 静态映射 / 文案表（不依赖 actor 状态，static 方便测试单独调用）

    /// 排序谓词：让 effective Set 遍历顺序对外稳定（基于 case discriminant + 关联值字符串）
    /// - Parameters:
    ///   - lhs: 左侧 permission
    ///   - rhs: 右侧 permission
    /// - Returns: lhs < rhs 时 true
    private static func permissionOrdering(_ lhs: Permission, _ rhs: Permission) -> Bool {
        Self.canonicalKey(for: lhs) < Self.canonicalKey(for: rhs)
    }

    /// 给 Permission 生成可比较的 canonical key（仅用于 Set 排序，非业务语义）
    /// - Parameter permission: 输入 permission
    /// - Returns: 形如 "01:network|api.openai.com" 的字符串；前缀 2 位整数对应 case 顺序
    private static func canonicalKey(for permission: Permission) -> String {
        switch permission {
        case .network(let host):           return "01:network|\(host)"
        case .fileRead(let path):          return "02:fileRead|\(path)"
        case .fileWrite(let path):         return "03:fileWrite|\(path)"
        case .clipboard:                   return "04:clipboard"
        case .clipboardHistory:            return "05:clipboardHistory"
        case .shellExec(let cmds):         return "06:shellExec|\(cmds.joined(separator: ","))"
        case .mcp(let server, let tools):  return "07:mcp|\(server)|\(tools?.joined(separator: ",") ?? "*")"
        case .screen:                      return "08:screen"
        case .systemAudio:                 return "09:systemAudio"
        case .memoryAccess(let scope):     return "10:memoryAccess|\(scope)"
        case .appIntents(let bundleId):    return "11:appIntents|\(bundleId)"
        }
    }

    /// 把 SliceCore `Permission` 11 case 映射到 5 档 tier
    ///
    /// **保守归类原则**（M2 安全姿态；M3+ Permission 加关联值后下放精度）：
    /// - `.clipboard`：M1 case 不区分读 / 写方向 → 归 localWrite（包含潜在写）
    /// - `.network`：M1 case 不区分 GET / POST → 归 networkWrite
    /// - `.mcp`：spec 区分 readonly / write → 保守归 networkWrite
    /// - `.systemAudio`：TTS / 朗读 = 写系统音频通道 → localWrite
    /// - `.screen`：截屏不联网不写本地 → readonlyLocal
    /// - Parameter permission: 输入 permission
    /// - Returns: 5 档 tier 之一
    internal static func inferTier(_ permission: Permission) -> PermissionTier {
        switch permission {
        case .fileRead, .clipboardHistory, .memoryAccess, .screen:
            return .readonlyLocal
        case .fileWrite, .clipboard, .systemAudio:
            return .localWrite
        case .network, .mcp:
            return .networkWrite
        case .shellExec, .appIntents:
            return .exec
        }
    }

    /// 哪些 tier 的 grant 可被缓存（即"首次确认 → 后续静默"）
    ///
    /// network-write / exec **每次确认**，永不缓存（D-22 不可逆副作用必须逐次可审）
    /// - Parameter tier: 5 档 tier
    /// - Returns: true = first-time-confirm 后续可走 grant store；false = each-time 永不缓存
    internal static func cacheable(tier: PermissionTier) -> Bool {
        switch tier {
        case .readonlyLocal, .readonlyNetwork, .localWrite:
            return true
        case .networkWrite, .exec:
            return false
        }
    }

    /// 按 §3.9.1 表生成 ConsentUXHint 文案
    ///
    /// 文案仅 KISS 形态——含 tier + provenance 标识，便于 Playground UI 直接展示；
    /// 生产路径（M3+）若 hint 升级为 struct，本函数同步替换。
    /// - Parameters:
    ///   - tier: 5 档 tier
    ///   - provenance: 工具来源
    /// - Returns: 文案 hint 字符串
    internal static func uxHint(tier: PermissionTier, provenance: Provenance) -> ConsentUXHint {
        let tierLabel: String
        switch tier {
        case .readonlyLocal:   tierLabel = "readonly-local"
        case .readonlyNetwork: tierLabel = "readonly-network"
        case .localWrite:      tierLabel = "local-write"
        case .networkWrite:    tierLabel = "network-write"
        case .exec:            tierLabel = "exec"
        }
        let provenanceLabel: String
        switch provenance {
        case .firstParty:        provenanceLabel = "firstParty"
        case .communitySigned:   provenanceLabel = "communitySigned"
        case .selfManaged:       provenanceLabel = "selfManaged"
        case .unknown:           provenanceLabel = "unknown"
        }
        // 文案差异（spec §3.9.1）：firstParty 中性 / unknown 警告
        let copy: String
        switch provenance {
        case .firstParty, .communitySigned, .selfManaged:
            copy = "Authorize the following operation?"
        case .unknown:
            copy = "Source not verified, continue?"
        }
        return "[\(tierLabel)|\(provenanceLabel)] \(copy)"
    }
}
