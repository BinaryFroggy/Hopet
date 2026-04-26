import SwiftUI

struct OverviewTab: View {
    @ObservedObject var registry: SessionRegistry
    let controller: PetWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pets").font(.headline)
            HStack(spacing: 16) {
                ForEach(SessionRegistry.activeTools, id: \.self) { tool in
                    PetCard(
                        tool: tool,
                        pet: registry.pets[tool] ?? PetInstance(tool: tool),
                        sessionCount: registry.activeSessions(of: tool).count,
                        onLocate: { controller.locate(tool) }
                    )
                }
            }
            Divider()
            Text("Sessions (\(registry.sessions.count))").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(registry.sessions.values.sorted(by: { $0.startedAt < $1.startedAt }), id: \.id) { s in
                        HStack {
                            Circle().fill(s.currentState.accentColor).frame(width: 8, height: 8)
                            Text(s.tool.displayName).font(.system(size: 11, weight: .semibold))
                            Text(s.displayTitle).font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Text(s.currentState.badgeText).font(.system(size: 11)).foregroundStyle(s.currentState.accentColor)
                            Text(s.elapsedDescription()).font(.system(size: 11, design: .monospaced))
                            Button("×") { registry.remove(s.id) }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                    if registry.sessions.isEmpty {
                        Text("还没有活跃 session。安装 Hooks 后启动 Claude Code 即可看到。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }
            }
            Spacer()
        }
        .padding(8)
    }
}

private struct PetCard: View {
    let tool: AITool
    let pet: PetInstance
    let sessionCount: Int
    let onLocate: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(pet.aggregatedState.badgeText)
                .font(.system(size: 24))
            Text(tool.displayName).font(.headline)
            Text("\(sessionCount) session(s)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("Locate") { onLocate() }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(width: 160, height: 140)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(pet.aggregatedState.accentColor, lineWidth: 1.5))
    }
}
