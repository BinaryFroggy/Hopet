import Foundation

/// 单 session 状态转换函数（架构文档 §7.1 / §7.2）。
/// 纯函数，方便单测；不直接持有 Session。
public enum SessionStateMachine {
    /// 给定当前状态与事件，返回下一状态；返回 nil 表示「忽略该事件，状态不变」。
    public static func nextState(from current: PetState, event: EventKind) -> PetState? {
        switch (current, event) {
        case (_, .sessionStart):
            return .idle

        // user_prompt：从 idle / errorInterrupted / askUser 都可以进入 responding
        case (_, .userPrompt):
            return .responding

        // thinking_start：仅 responding 升级到 thinking
        case (.responding, .thinkingStart):
            return .thinking

        // pre_tool_use：responding / thinking → toolUse
        case (.responding, .preToolUse), (.thinking, .preToolUse), (.idle, .preToolUse):
            return .toolUse

        // post_tool_use：toolUse / permissionPrompt → responding
        case (.toolUse, .postToolUse),
             (.permissionPrompt, .postToolUse):
            return .responding

        // permission_ask：responding / thinking / toolUse → permissionPrompt
        case (.responding, .permissionAsk),
             (.thinking, .permissionAsk),
             (.toolUse, .permissionAsk):
            return .permissionPrompt

        // ask_user：从任意主动状态进入 askUser
        case (.responding, .askUser),
             (.thinking, .askUser),
             (.toolUse, .askUser),
             (.idle, .askUser):
            return .askUser

        // ask_user_resolved：从 askUser 回到 responding
        case (.askUser, .askUserResolved):
            return .responding

        // 错误：任意状态进入 errorInterrupted
        case (_, .error):
            return .errorInterrupted

        // stop：任意活跃状态进入 completed
        case (.responding, .stop),
             (.thinking, .stop),
             (.toolUse, .stop),
             (.permissionPrompt, .stop),
             (.askUser, .stop):
            return .completed

        case (.completed, .stop), (.idle, .stop), (.errorInterrupted, .stop):
            return nil

        default:
            return nil
        }
    }
}
