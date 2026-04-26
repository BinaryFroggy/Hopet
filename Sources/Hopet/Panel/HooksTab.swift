import SwiftUI

struct HooksTab: View {
    let installer: HookInstaller
    @State private var doctorReport: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hook Installation").font(.headline)
            HookCard(
                tool: .claudeCode,
                isInstalled: installer.isInstalled(.claudeCode),
                onInstall: { _ = try? installer.install(.claudeCode); refresh() },
                onUninstall: { _ = try? installer.uninstall(.claudeCode); refresh() }
            )
            Text("Codex 在 v0.2 启用。").font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Run Hook Doctor") {
                    doctorReport = HookDoctor.run(installer: installer)
                }
                Spacer()
            }
            ScrollView {
                Text(doctorReport.isEmpty ? "Doctor 输出会出现在这里。" : doctorReport)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxHeight: 180)
        }
        .padding(8)
    }

    private func refresh() {
        doctorReport = HookDoctor.run(installer: installer)
    }
}

private struct HookCard: View {
    let tool: AITool
    let isInstalled: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isInstalled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isInstalled ? .green : .orange)
            Text(tool.displayName).font(.system(size: 13, weight: .semibold))
            Text(isInstalled ? "Installed" : "Not installed")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            if isInstalled {
                Button("Reinstall") { onInstall() }
                Button("Uninstall") { onUninstall() }
            } else {
                Button("Install") { onInstall() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
    }
}
