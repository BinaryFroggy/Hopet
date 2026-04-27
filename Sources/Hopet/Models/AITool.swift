import Foundation

/// 接入的 AI 工具枚举。每个 case 对应一只宠物（PetInstance）。
public enum AITool: String, Codable, CaseIterable, Hashable, Sendable {
    case claudeCode = "claude-code"
    case codex      = "codex"
    case custom

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codex:      return "Codex"
        case .custom:     return "Custom"
        }
    }

    /// 启动该 AI CLI 的可执行文件名（在 PATH 上查找）。Custom 暂未支持。
    public var cliBinary: String? {
        switch self {
        case .claudeCode: return "claude"
        case .codex:      return "codex"
        case .custom:     return nil
        }
    }
}
