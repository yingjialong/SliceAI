import Foundation

/// Orchestration 执行层的占位符，仅用于让 SwiftPM 可构建空 target
/// M2 里会被真实类型（ExecutionEngine / ContextCollector / PermissionBroker 等）替代并删除
internal enum OrchestrationPlaceholder {}
