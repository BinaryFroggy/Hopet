import SwiftUI

/// 概览：单张 PetCard 显示全局宠物的聚合状态 + 活跃 session 数；下方是会话列表。
/// See preferences.md §11.6.
struct OverviewTab: View {
    @ObservedObject var registry: SessionRegistry
    @AppStorage("notch.enabled") private var notchVisible: Bool = true
    @AppStorage("pet.visible") private var petVisible: Bool = true
    let controller: PetWindowController

    var body: some View {
        PreferencesPaneScaffold("Overview") {
            HStack(spacing: 12) {
                PixelPetCard(
                    pet: registry.pet,
                    sessionCount: registry.sessions.count,
                    onLocate: {
                        petVisible = true
                        controller.locate()
                    }
                )
                PixelDisplayCard(
                    notchVisible: $notchVisible,
                    petVisible: $petVisible
                )
                Spacer(minLength: 0)
            }

            PixelCard("SESSIONS", titleTint: PixelPalette.lemon) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(registry.sessions.count) active")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))

                    if registry.sessions.isEmpty {
                        Text("No active sessions yet. Trigger a Claude Code or Codex run to see one here.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(
                            registry.sessions.values.sorted(by: { $0.startedAt < $1.startedAt }),
                            id: \.id
                        ) { session in
                            SessionRow(session: session) {
                                registry.remove(session.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct PixelDisplayCard: View {
    @Binding var notchVisible: Bool
    @Binding var petVisible: Bool

    var body: some View {
        PixelCard("DISPLAY", titleTint: PixelPalette.candyPink) {
            VStack(alignment: .leading, spacing: 10) {
                PixelToggleRow(label: "Show notch bar", isOn: $notchVisible)
                PixelToggleRow(label: "Show pet", isOn: $petVisible)
            }
            .frame(width: 220, height: 120, alignment: .topLeading)
        }
    }
}

private struct PixelPetCard: View {
    let pet: PetInstance
    let sessionCount: Int
    let onLocate: () -> Void

    var body: some View {
        PixelCard("HOPET", accent: pet.aggregatedState.accentColor, titleTint: PixelPalette.sky) {
            VStack(spacing: 6) {
                Text(pet.aggregatedState.glyph)
                    .font(.system(size: 26))
                Text("\(sessionCount) session(s)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Locate", action: onLocate)
                    .buttonStyle(PixelButtonStyle(tint: PixelPalette.sky, prominent: false))
            }
            .frame(width: 140, height: 120)
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(session.currentState.accentColor).frame(width: 8, height: 8)
            Text(session.tool.displayName)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text(session.displayTitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(session.currentState.badgeLabel)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(session.currentState.accentColor)
            Text(session.elapsedDescription())
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Button("×", action: onRemove)
                .buttonStyle(PixelButtonStyle(tint: .gray, prominent: false))
        }
        .padding(.vertical, 2)
    }
}
