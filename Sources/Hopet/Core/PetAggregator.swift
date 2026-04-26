import Foundation
import Combine

/// 把多 session → 单宠物的优先级聚合，权威算法见 hooks-and-priority.md §3.2。
@MainActor
public final class PetAggregator {
    private unowned let registry: SessionRegistry
    private var bag = Set<AnyCancellable>()

    public init(registry: SessionRegistry) {
        self.registry = registry
        registry.mutations
            .receive(on: RunLoop.main)
            .sink { [weak self] mutation in
                guard let self else { return }
                switch mutation {
                case .added(_, let tool),
                     .removed(_, let tool),
                     .stateChanged(_, let tool, _, _):
                    self.recompute(tool: tool)
                case .fieldsUpdated:
                    break
                }
            }
            .store(in: &bag)

        for tool in registry.pets.keys { recompute(tool: tool) }
    }

    public func recompute(tool: AITool) {
        guard let current = registry.pets[tool] else { return }
        let active = registry.activeSessions(of: tool)
        let newState: PetState
        let newDriver: String?
        if active.isEmpty {
            newState = .idle
            newDriver = nil
        } else {
            let leader = active.sorted { a, b in
                let pa = a.currentState.priority
                let pb = b.currentState.priority
                if pa != pb { return pa < pb }
                if a.stateSince != b.stateSince { return a.stateSince > b.stateSince }
                return a.id < b.id
            }.first!
            newState = leader.currentState
            newDriver = leader.id
        }
        guard current.aggregatedState != newState || current.drivenBySessionId != newDriver else { return }
        registry.updatePet(tool) {
            $0.aggregatedState = newState
            $0.drivenBySessionId = newDriver
        }
    }
}
