import Foundation
import Combine

/// 所有活跃 Session 的注册表。线程安全（@MainActor，配合 Combine UI 链路）。
@MainActor
public final class SessionRegistry: ObservableObject {
    @Published public private(set) var sessions: [String: Session] = [:]
    @Published public private(set) var pets: [AITool: PetInstance] = [:]

    /// 「单 session 状态变化 / 加入 / 移除」的细粒度变更广播。
    public let mutations = PassthroughSubject<Mutation, Never>()

    public enum Mutation: Sendable {
        case added(sessionId: String, tool: AITool)
        case stateChanged(sessionId: String, tool: AITool, from: PetState, to: PetState)
        case removed(sessionId: String, tool: AITool)
        case fieldsUpdated(sessionId: String)
    }

    /// v0.1：只为 Claude 创建宠物实例。Codex 留到 v0.2，那时 hooks 也成熟。
    public static let activeTools: [AITool] = [.claudeCode]

    public init() {
        for tool in Self.activeTools {
            pets[tool] = PetInstance(tool: tool, screenPosition: defaultPosition(for: tool))
        }
    }

    private func defaultPosition(for tool: AITool) -> CGPoint {
        // 主屏右下，Codex 再向左偏移 200。具体 frame 在 PetWindow 创建时再 clamp。
        let baseX: CGFloat = 1400
        let baseY: CGFloat = 200
        switch tool {
        case .claudeCode: return CGPoint(x: baseX, y: baseY)
        case .codex:      return CGPoint(x: baseX - 200, y: baseY)
        case .custom:     return CGPoint(x: baseX - 400, y: baseY)
        }
    }

    // MARK: - Mutations

    @discardableResult
    public func upsert(_ session: Session) -> Bool {
        let isNew = sessions[session.id] == nil
        sessions[session.id] = session
        if isNew {
            HopetLog.trace("reg+", "added sid=\(session.id.hopetShortId) tool=\(session.tool.rawValue) cwd=\(session.cwdLastComponent)")
            mutations.send(.added(sessionId: session.id, tool: session.tool))
        } else {
            mutations.send(.fieldsUpdated(sessionId: session.id))
        }
        return isNew
    }

    public func remove(_ sessionId: String) {
        guard let s = sessions.removeValue(forKey: sessionId) else { return }
        HopetLog.trace("reg-", "removed sid=\(sessionId.hopetShortId) tool=\(s.tool.rawValue)")
        mutations.send(.removed(sessionId: sessionId, tool: s.tool))
    }

    /// 单点状态切换。会广播 stateChanged。
    public func transition(sessionId: String, to newState: PetState, at timestamp: Date = Date()) {
        guard var s = sessions[sessionId] else { return }
        let old = s.currentState
        guard old != newState else { return }
        s.currentState = newState
        s.stateSince = timestamp
        sessions[sessionId] = s
        HopetLog.trace("state", "sid=\(sessionId.hopetShortId) \(old.rawValue) → \(newState.rawValue)")
        mutations.send(.stateChanged(sessionId: sessionId, tool: s.tool, from: old, to: newState))
    }

    public func patch(_ sessionId: String, _ block: (inout Session) -> Void) {
        guard var s = sessions[sessionId] else { return }
        let original = s
        block(&s)
        guard s != original else { return }
        sessions[sessionId] = s
        mutations.send(.fieldsUpdated(sessionId: sessionId))
    }

    public func activeSessions(of tool: AITool) -> [Session] {
        sessions.values.filter { $0.tool == tool }
    }

    public func session(_ id: String) -> Session? { sessions[id] }

    // MARK: - Pet aggregation hook

    public func updatePet(_ tool: AITool, mutate: (inout PetInstance) -> Void) {
        guard var p = pets[tool] else { return }
        mutate(&p)
        pets[tool] = p
    }
}
