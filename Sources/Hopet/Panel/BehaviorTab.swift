import SwiftUI

/// 行为偏好：开机自启、刘海条、终端、日志级别。所有控件用像素风部件，全 monospaced。
/// See preferences.md §11.6.
struct BehaviorTab: View {
    @AppStorage("general.launchAtLogin")        private var launchAtLogin: Bool = false
    @AppStorage("notch.enabled")                private var notchEnabled: Bool = true
    @AppStorage("notch.fallbackBarEnabled")     private var notchFallback: Bool = false
    @AppStorage("pet.snapToEdge")               private var snapToEdge: Bool = true
    @AppStorage("bubble.preferredTerminal")     private var preferredTerminal: String = "Terminal.app"
    @AppStorage("bubble.recordPromptSummary")   private var recordPromptSummary: Bool = true
    @AppStorage("advanced.logLevel")            private var logLevel: String = "info"

    var body: some View {
        PreferencesPaneScaffold("Behavior") {
            sectionGeneral
            sectionNotch
            sectionTerminal
            sectionDiagnostics
        }
    }

    private var sectionGeneral: some View {
        PixelCard("GENERAL", titleTint: PixelPalette.sky) {
            VStack(alignment: .leading, spacing: 10) {
                PixelToggleRow(label: "Launch at login", isOn: $launchAtLogin)
                PixelToggleRow(label: "Snap to screen edge on release", isOn: $snapToEdge)
                PixelToggleRow(label: "Keep 256-char prompt summary", isOn: $recordPromptSummary)
            }
        }
    }

    private var sectionNotch: some View {
        PixelCard("NOTCH", titleTint: PixelPalette.candyPink) {
            VStack(alignment: .leading, spacing: 10) {
                PixelToggleRow(label: "Enable notch indicator", isOn: $notchEnabled)
                PixelToggleRow(label: "Fallback top bar on non-notch displays", isOn: $notchFallback)
            }
        }
    }

    private var sectionTerminal: some View {
        PixelCard("TERMINAL", titleTint: PixelPalette.mint) {
            VStack(alignment: .leading, spacing: 10) {
                PixelSegmentedControl(
                    selection: $preferredTerminal,
                    options: [
                        ("Terminal.app", "Terminal"),
                        ("iTerm2",       "iTerm2"),
                    ]
                )
            }
        }
    }

    private var sectionDiagnostics: some View {
        PixelCard("DIAGNOSTICS", titleTint: PixelPalette.lemon) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Log level")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                PixelSegmentedControl(
                    selection: $logLevel,
                    options: [
                        ("error", "Error"),
                        ("warn",  "Warn"),
                        ("info",  "Info"),
                        ("debug", "Debug"),
                    ]
                )
            }
        }
    }
}

