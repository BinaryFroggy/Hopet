import SwiftUI

struct BehaviorTab: View {
    @AppStorage("general.launchAtLogin")        private var launchAtLogin: Bool = false
    @AppStorage("notch.enabled")                private var notchEnabled: Bool = true
    @AppStorage("notch.fallbackBarEnabled")     private var notchFallback: Bool = false
    @AppStorage("pet.snapToEdge")               private var snapToEdge: Bool = true
    @AppStorage("bubble.preferredTerminal")     private var preferredTerminal: String = "Terminal.app"
    @AppStorage("bubble.recordPromptSummary")   private var recordPromptSummary: Bool = true
    @AppStorage("advanced.logLevel")            private var logLevel: String = "info"

    var body: some View {
        Form {
            Section("General") {
                Toggle("开机自启", isOn: $launchAtLogin)
                Toggle("拖拽松手吸附屏幕边缘", isOn: $snapToEdge)
                Toggle("保留 prompt 256 字符摘要", isOn: $recordPromptSummary)
            }
            Section("Notch") {
                Toggle("启用刘海条", isOn: $notchEnabled)
                Toggle("无刘海机型显示降级顶条", isOn: $notchFallback)
            }
            Section("Terminal") {
                Picker("首选终端", selection: $preferredTerminal) {
                    Text("Terminal.app").tag("Terminal.app")
                    Text("iTerm2").tag("iTerm2")
                }
            }
            Section("Diagnostics") {
                Picker("日志级别", selection: $logLevel) {
                    ForEach(["error", "warn", "info", "debug"], id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
