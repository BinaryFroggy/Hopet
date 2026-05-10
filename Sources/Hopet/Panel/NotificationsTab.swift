import SwiftUI

/// 通知偏好。所有 Toggle 用 PixelToggle，与气泡同语言。
/// See preferences.md §11.6.
struct NotificationsTab: View {
    @AppStorage("notifications.permissionPrompt") private var permissionPrompt: Bool = true
    @AppStorage("notifications.askUser")          private var askUser: Bool = true
    @AppStorage("notifications.completed")        private var completed: Bool = false
    @AppStorage("notifications.error")            private var errorAlert: Bool = true

    var body: some View {
        PreferencesPaneScaffold("Notifications") {
            PixelCard("BANNERS", titleTint: PixelPalette.sky) {
                VStack(alignment: .leading, spacing: 10) {
                    PixelToggleRow(label: "Permission prompt",  isOn: $permissionPrompt)
                    PixelToggleRow(label: "Ask-user question",  isOn: $askUser)
                    PixelToggleRow(label: "Session completed",  isOn: $completed)
                    PixelToggleRow(label: "Error / interrupt", isOn: $errorAlert)
                }
            }

            PixelCard("SOUND", titleTint: PixelPalette.lemon) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Themes will ship per-state sound effects in v0.2.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

