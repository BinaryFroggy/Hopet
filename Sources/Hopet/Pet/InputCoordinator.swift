import Foundation

/// 转发气泡 UI 上的两类同步决策给 PermissionPrompter，让它通过挂起的 socket
/// 回写到 hopet-emit、再到 Claude。
///
/// v0.1 不再做任何"点宠物本体启动新会话"或"在气泡里输入消息注入到 session"的功能
/// （详见 architecture.md §12.5），所以这里也没有相应方法。
@MainActor
public final class InputCoordinator {
    private unowned let registry: SessionRegistry
    private unowned let permissionPrompter: PermissionPrompter

    public init(registry: SessionRegistry, permissionPrompter: PermissionPrompter) {
        self.registry = registry
        self.permissionPrompter = permissionPrompter
    }

    /// 用户在气泡 UI 上点 Allow / Deny / Ask 时调用。
    /// `reason` 仅在 deny 时使用，承载 plan-approval 卡片的"继续规划"或自定义反馈文案。
    public func resolvePermission(sessionId: String, requestId: String, decision: String, reason: String? = nil) {
        permissionPrompter.resolve(
            sessionId: sessionId,
            requestId: requestId,
            decision: decision,
            reason: reason
        )
    }

    /// 用户在 AskUserQuestion 气泡里提交答案时调用。
    /// answers: 问题文案 → 用户作答字符串。cancel = true 表示让 Claude 走自身 UI。
    public func resolveAskUser(sessionId: String, requestId: String, answers: [String: String], cancel: Bool = false) {
        permissionPrompter.resolveAskUser(
            sessionId: sessionId,
            requestId: requestId,
            answers: answers,
            cancel: cancel
        )
    }
}
