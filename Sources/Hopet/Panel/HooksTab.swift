import SwiftUI

/// 监听设置：每个工具一行 Toggle，勾选 = 安装 hooks，取消 = 卸载。
/// Codex 在 v0.2 占位（底层 install 报 unimplemented，UI 仍允许勾选写入 config，启动期同步会 warn）。
/// See preferences.md §3 / §6.1 / §11.6.
struct HooksTab: View {
    let installer: HookInstaller
    @ObservedObject var configStore: ConfigStore
    @State private var doctorReport: String = ""

    var body: some View {
        PreferencesPaneScaffold("Listeners") {
            HookToggleRow(
                tool: .claudeCode,
                isOn: Binding(
                    get: { configStore.current.listeners.claudeCode },
                    set: { v in configStore.update { $0.listeners.claudeCode = v } }
                ),
                isInstalled: installer.isInstalled(.claudeCode)
            )

            HookToggleRow(
                tool: .codex,
                isOn: Binding(
                    get: { configStore.current.listeners.codex },
                    set: { v in configStore.update { $0.listeners.codex = v } }
                ),
                isInstalled: installer.isInstalled(.codex),
                placeholderNote: "Codex 在 v0.3 启用：勾选当前仅写入偏好，不会真正安装。"
            )

            DoctorBlock(installer: installer, report: $doctorReport)
        }
    }
}

private struct HookToggleRow: View {
    let tool: AITool
    @Binding var isOn: Bool
    let isInstalled: Bool
    var placeholderNote: String? = nil

    var body: some View {
        PixelCard(tool.displayName.uppercased(), accent: .accentColor, titleTint: PixelPalette.sky) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isInstalled ? "Installed" : "Not installed")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isInstalled ? PixelPalette.mint : .secondary)
                    if let placeholderNote {
                        Text(placeholderNote)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(isOn ? "Hopet listens to this terminal." : "Listening disabled.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                PixelToggle(isOn: $isOn, tint: .accentColor)
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
                    .buttonStyle(PixelButtonStyle(tint: .accentColor, prominent: false))
                }

                ScrollView {
                    Text(report.isEmpty ? "Doctor 输出会出现在这里。" : report)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
            }
        }
    }
}
