import Foundation
import Combine

/// 所有活跃 Session 的注册表。线程安全（@MainActor，配合 Combine UI 链路）。
@MainActor
public final class SessionRegistry: ObservableObject {
    @Published public private(set) var sessions: [String: Session] = [:]
    /// 全局唯一宠物（v0.x 起：所有 AI 工具共用一只）。
    @Published public private(set) var pet: PetInstance

    /// 「单 session 状态变化 / 加入 / 移除」的细粒度变更广播。
    public let mutations = PassthroughSubject<Mutation, Never>()

    public enum Mutation: Sendable {
        case added(sessionId: String, tool: AITool)
        case stateChanged(sessionId: String, tool: AITool, from: PetState, to: PetState)
        case removed(sessionId: String, tool: AITool)
        case fieldsUpdated(sessionId: String)
    }

    public init() {
        self.pet = PetInstance(screenPosition: Self.defaultPosition())
    }

    /// 全局宠物默认位置。后续若引入位置持久化，会读 ConfigStore。
    private static func defaultPosition() -> CGPoint {
        CGPoint(x: 1400, y: 200)
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

    /// 同工具的活跃 session。`EventRouter.pruneStaleSiblings` 等仍按 tool 维度判定"同一终端的躺尸"。
    public func activeSessions(of tool: AITool) -> [Session] {
        sessions.values.filter { $0.tool == tool }
    }

    /// 所有活跃 session（跨 tool）。PetAggregator / PetStageView 消费此列表。
    public var activeSessions: [Session] {
        Array(sessions.values)
    }

    public func session(_ id: String) -> Session? { sessions[id] }

    // MARK: - Pet aggregation hook

    public func updatePet(_ mutate: (inout PetInstance) -> Void) {
        var p = pet
        mutate(&p)
        pet = p
    }
}
