import SwiftUI

struct NotificationsTab: View {
    @AppStorage("notifications.permissionPrompt") private var permissionPrompt: Bool = true
    @AppStorage("notifications.askUser")          private var askUser: Bool = true
    @AppStorage("notifications.completed")        private var completed: Bool = false
    @AppStorage("notifications.error")            private var errorAlert: Bool = true

    var body: some View {
        Form {
            Section("Banners") {
                Toggle("权限请求", isOn: $permissionPrompt)
                Toggle("AskUserQuestion", isOn: $askUser)
                Toggle("完成通知", isOn: $completed)
                Toggle("错误中断", isOn: $errorAlert)
            }
            Section("Sound (v0.2)") {
                Text("v0.2 启用主题自带声音。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
