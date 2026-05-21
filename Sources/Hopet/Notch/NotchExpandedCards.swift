import SwiftUI

// MARK: - 公共头部

/// 灵动岛展开卡片公共顶栏：状态点 + 标题 + 副标题 + 右上角关闭按钮。
/// `onClose` 由容器注入：点击 = 关闭整个灵动岛（写 notch.enabled = false）。
struct NotchCardHeader: View {
    let accent: Color
    let title: String
    let subtitle: String?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if let s = subtitle, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("关闭灵动岛")
        }
    }
}

// MARK: - PermissionCard

struct NotchPermissionCard: View {
    let session: Session
    let pending: PendingPermission
    let onResolve: (_ decision: String, _ reason: String?) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NotchCardHeader(
                accent: .orange,
                title: "权限请求 · \(pending.toolName)",
                subtitle: session.displayTitle,
                onClose: onClose
            )

            if let cmd = pending.command, !cmd.isEmpty {
                NotchCommandPreview(label: "命令", text: cmd)
            } else if let path = pending.filePath, !path.isEmpty {
                NotchCommandPreview(label: "文件", text: path)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("拒绝") { onResolve("deny", nil) }
                    .buttonStyle(NotchPillButtonStyle(tint: Color(red: 0.92, green: 0.32, blue: 0.50)))
                Button("允许") { onResolve("allow", nil) }
                    .buttonStyle(NotchPillButtonStyle(tint: Color(red: 0.30, green: 0.78, blue: 0.45)))
            }
        }
        .padding(16)
    }
}

// MARK: - PlanApprovalCard

struct NotchPlanApprovalCard: View {
    let session: Session
    let pending: PendingPermission
    let onResolve: (_ decision: String, _ reason: String?) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NotchCardHeader(
                accent: Color(red: 0.49, green: 0.78, blue: 0.96),
                title: "计划评审",
                subtitle: session.displayTitle,
                onClose: onClose
            )

            ScrollView {
                Text(pending.plan ?? "（未提供计划正文）")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.06))
                    )
            }

            HStack(spacing: 10) {
                Button("继续规划") {
                    onResolve("deny", "User wants to keep planning")
                }
                .buttonStyle(NotchPillButtonStyle(tint: Color(white: 0.62)))
                Button("批准执行") {
                    onResolve("allow", nil)
                }
                .buttonStyle(NotchPillButtonStyle(tint: Color(red: 0.30, green: 0.78, blue: 0.45)))
            }
        }
        .padding(16)
    }
}

// MARK: - AskUserCard

struct NotchAskUserCard: View {
    let session: Session
    let pending: PendingAskUser
    let onSubmit: (_ answers: [String: String], _ cancel: Bool) -> Void
    let onClose: () -> Void

    @State private var index: Int = 0
    @State private var answers: [String: String] = [:]
    /// multi-select 暂存：问题 → 已勾选 label 数组（保持点击顺序）。
    @State private var selected: [String: [String]] = [:]
    /// 单问题无 options 时的自由文本暂存。
    @State private var freeText: [String: String] = [:]

    private var questions: [AskUserQuestionItem] { pending.questions }
    private var current: AskUserQuestionItem? {
        questions.indices.contains(index) ? questions[index] : nil
    }
    private var isLast: Bool { index >= questions.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NotchCardHeader(
                accent: Color(red: 0.96, green: 0.78, blue: 0.36),
                title: "等待回答",
                subtitle: pageIndicator,
                onClose: onClose
            )

            if let q = current {
                Text(q.question)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let options = q.options, !options.isEmpty {
                            ForEach(options, id: \.label) { opt in
                                optionRow(for: opt, in: q)
                            }
                        } else {
                            TextField("输入回答…", text: freeTextBinding(for: q))
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.08))
                                )
                                .foregroundStyle(.white)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button("交还终端") { onSubmit([:], true) }
                    .buttonStyle(NotchPillButtonStyle(tint: Color(white: 0.62)))
                Spacer()
                if !isLast, currentSatisfied {
                    Button("下一题") { withAnimation(.easeOut(duration: 0.18)) { index += 1 } }
                        .buttonStyle(NotchPillButtonStyle(tint: Color(red: 0.49, green: 0.78, blue: 0.96)))
                }
                Button(isLast ? "提交" : "跳到末页") {
                    if isLast { submitAll() } else { index = questions.count - 1 }
                }
                .buttonStyle(NotchPillButtonStyle(tint: Color(red: 0.30, green: 0.78, blue: 0.45)))
                .disabled(!isLast || !allSatisfied)
            }
        }
        .padding(16)
    }

    private var pageIndicator: String {
        questions.count > 1 ? "第 \(index + 1) / \(questions.count) 题 · \(session.displayTitle)" : session.displayTitle
    }

    @ViewBuilder
    private func optionRow(for opt: AskUserQuestionOption, in q: AskUserQuestionItem) -> some View {
        let multi = q.multiSelect ?? false
        let chosen: Bool = {
            if multi { return (selected[q.question] ?? []).contains(opt.label) }
            return answers[q.question] == opt.label
        }()
        Button {
            tapOption(opt, in: q, multi: multi)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: multi
                      ? (chosen ? "checkmark.square.fill" : "square")
                      : (chosen ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(chosen ? Color.accentColor : .white.opacity(0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(opt.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                    if let d = opt.description, !d.isEmpty {
                        Text(d)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(chosen ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    private func tapOption(_ opt: AskUserQuestionOption, in q: AskUserQuestionItem, multi: Bool) {
        if multi {
            var cur = selected[q.question] ?? []
            if let i = cur.firstIndex(of: opt.label) {
                cur.remove(at: i)
            } else {
                cur.append(opt.label)
            }
            selected[q.question] = cur
            answers[q.question] = cur.joined(separator: ", ")
        } else {
            answers[q.question] = opt.label
            if !isLast, currentSatisfied {
                withAnimation(.easeOut(duration: 0.18)) { index += 1 }
            }
        }
    }

    private func freeTextBinding(for q: AskUserQuestionItem) -> Binding<String> {
        Binding(
            get: { freeText[q.question] ?? "" },
            set: { v in
                freeText[q.question] = v
                answers[q.question] = v
            }
        )
    }

    private var currentSatisfied: Bool {
        guard let q = current else { return false }
        let v = answers[q.question] ?? ""
        return !v.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var allSatisfied: Bool {
        questions.allSatisfy { q in
            let v = answers[q.question] ?? ""
            return !v.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func submitAll() {
        onSubmit(answers, false)
    }
}

// MARK: - CompletedSummaryCard

struct NotchCompletedSummaryCard: View {
    let session: Session
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NotchCardHeader(
                accent: Color(red: 0.30, green: 0.78, blue: 0.45),
                title: "会话完成 · \(session.tool.displayName)",
                subtitle: session.displayTitle,
                onClose: onClose
            )

            Text(session.lastAssistantMessage ?? "—")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }
}

// MARK: - 小组件

/// 命令 / 文件路径预览块。等宽字体、半透明描边，避免长命令被默认字体撑形。
private struct NotchCommandPreview: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(3)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
        }
    }
}

/// 灵动岛卡片专用按钮样式：胶囊背景 + 白字 + 轻按压反馈。tint 决定主色。
struct NotchPillButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(tint.opacity(configuration.isPressed ? 0.65 : 0.90))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
