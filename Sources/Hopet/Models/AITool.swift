import Foundation

/// 接入的 AI 工具枚举。仅作为 Session 来源标签与 hook 路由白名单——
/// 宠物全局唯一，所有工具的 session 共用同一只 PetInstance。
public enum AITool: String, Codable, CaseIterable, Hashable, Sendable {
    case claudeCode = "claude-code"
    case codex      = "codex"
    case hopeAgent  = "hope-agent"
    case custom

    /// Hopet 当前识别的 AI 工具集合。驱动 hook 安装、listener toggle、事件路由白名单等。
    /// `.custom` 暂未支持，第三方接入 API 等 v0.3。
    public static let recognized: [AITool] = [.claudeCode, .codex, .hopeAgent]

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codex:      return "Codex"
        case .hopeAgent:  return "Hope Agent"
        case .custom:     return "Custom"
        }
    }

    /// 启动该 AI CLI 的可执行文件名（在 PATH 上查找）。Custom 暂未支持。
    /// Hope Agent 是 GUI / 守护进程，不在 PATH 上以单一 CLI 形式启动，故为 nil；
    /// 它的"是否安装"按 `~/.hope-agent/config.json` 是否存在判定，见 HookInstaller。
    public var cliBinary: String? {
        switch self {
        case .claudeCode: return "claude"
        case .codex:      return "codex"
        case .hopeAgent:  return nil
        case .custom:     return nil
        }
    }
}
