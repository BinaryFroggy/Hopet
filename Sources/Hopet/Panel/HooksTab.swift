import SwiftUI

/// 监听设置：每个工具一行 Toggle，软静音开关（折中策略）。
/// hook 在 App 启动时已落盘到 ~/.claude/settings.json / ~/.codex/hooks.json，
/// 这里的 toggle 不影响 hook 文件本身。off 时：EventRouter 静默丢弃事件，
/// 同时 SceneRouter 立即清掉该工具下无待决策的气泡；仍挂着 permission/askUser
/// 的气泡留到用户落决策后再清。See preferences.md §3 / §6.1 / §11.6。
struct HooksTab: View {
    let installer: HookInstaller
    @ObservedObject var configStore: ConfigStore
    @State private var doctorReport: String = ""

    var body: some View {
        PreferencesPaneScaffold("Listeners") {
            ForEach(AITool.recognized, id: \.self) { tool in
                HookToggleRow(
                    tool: tool,
                    isOn: Binding(
                        get: { configStore.current.listeners[tool] },
                        set: { v in configStore.update { $0.listeners[tool] = v } }
                    )
                )
            }

            DoctorBlock(installer: installer, report: $doctorReport)
        }
    }
}

private struct HookToggleRow: View {
    let tool: AITool
    @Binding var isOn: Bool

    var body: some View {
        PixelCard(tool.displayName.uppercased(), accent: PixelPalette.sky, titleTint: PixelPalette.sky) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isOn ? "Listening on" : "Listening off")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isOn ? PixelPalette.mint : .secondary)
                    Text(isOn
                         ? "Hopet reacts to this terminal's hooks."
                         : "Hooks remain installed; idle bubbles cleared, pending ones drain.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                PixelToggle(isOn: $isOn, tint: PixelPalette.mint)
            }
        }
    }
}

private struct DoctorBlock: View {
    let installer: HookInstaller
    @Binding var report: String

    var body: some View {
        PixelCard("HOOK DOCTOR", titleTint: PixelPalette.lemon) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("socket, settings, and emit binary checks")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Run") {
                        report = HookDoctor.run(installer: installer)
                    }
                    .buttonStyle(PixelButtonStyle(tint: PixelPalette.sky, prominent: false))
                }

                ScrollView {
                    Text(report.isEmpty ? "Doctor output will appear here." : report)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
            }
        }
    }
}
