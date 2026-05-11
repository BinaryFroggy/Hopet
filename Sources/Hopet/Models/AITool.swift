import Foundation

/// 接入的 AI 工具枚举。仅作为 Session 来源标签与 hook 路由白名单——
/// 宠物全局唯一，所有工具的 session 共用同一只 PetInstance。
public enum AITool: String, Codable, CaseIterable, Hashable, Sendable {
    case claudeCode = "claude-code"
    case codex      = "codex"
    case custom

    /// Hopet 当前识别的 AI 工具集合。驱动 hook 安装、listener toggle、事件路由白名单等。
    /// `.custom` 暂未支持，第三方接入 API 等 v0.3。
    public static let recognized: [AITool] = [.claudeCode, .codex]

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
