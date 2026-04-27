import SwiftUI

/// 单个会话气泡。折叠态 64×64，展开态根据 pendingPermission / pendingAskUser / pendingQuestion 自适应。
///
/// 可交互的输入只出现在 PermissionRequest hook 同步打通的两条路径上：
/// - `pendingPermission`：Allow / Deny / Ask 按钮，回包通过挂起的 socket。
/// - `pendingAskUser`：结构化 AskUserQuestion 答题，回包带 `updatedInput.answers`。
///
/// 其它情况（idle / 旧 fire-and-forget pendingQuestion）只展示状态信息，
/// 不再提供"自由输入消息"入口——macOS 没有可靠的跨终端宿主反向 stdin 注入路径
/// （TIOCSTI 受 controlling tty 限制、AppleScript 仅 iTerm/Terminal、第三方进程
/// 拿不到 IDE/CLI extension spawn 的 PTY master fd）。
public struct SessionBubbleView: View {
    let bubble: SessionBubble
    let isLeader: Bool
    let elapsed: String
    let onTap: () -> Void
    let onResolvePermission: (String) -> Void  // "allow" / "deny" / "ask"
    /// AskUserQuestion 答题提交回调。`answers` 形如 `{ "问题文案": "回答" }`；
    /// `cancel = true` 表示用户取消（让 Claude 走自身 UI）。
    let onResolveAskUser: ([String: String], Bool) -> Void
    let onDismiss: () -> Void

    public init(
        bubble: SessionBubble,
        isLeader: Bool,
        elapsed: String,
        onTap: @escaping () -> Void,
        onResolvePermission: @escaping (String) -> Void = { _ in },
        onResolveAskUser: @escaping ([String: String], Bool) -> Void = { _, _ in },
        onDismiss: @escaping () -> Void
    ) {
        self.bubble = bubble
        self.isLeader = isLeader
        self.elapsed = elapsed
        self.onTap = onTap
        self.onResolvePermission = onResolvePermission
        self.onResolveAskUser = onResolveAskUser
        self.onDismiss = onDismiss
    }

    @FocusState private var inputFocused: Bool
    /// 结构化 AskUserQuestion 的答题暂存：问题文案 → 用户当前输入。
    @State private var elicitationAnswers: [String: String] = [:]
    /// 多问题时的当前页索引。单问题时恒为 0。
    @State private var elicitationIndex: Int = 0

    public var body: some View {
        Group {
            if bubble.expanded {
                expandedCard
            } else {
                collapsedDot
            }
        }
        .animation(.easeInOut(duration: 0.2), value: bubble.expanded)
    }

    private var collapsedDot: some View {
        VStack(spacing: 1) {
            Text("📁 \(bubble.displayCwd)")
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
            Text(bubble.displayTitle)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
            Text("⏱ \(elapsed)")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .padding(4)
        .frame(width: 64, height: 64)
        .background(
            Circle().fill(.ultraThinMaterial)
        )
        .overlay(
            Circle().stroke(bubble.state.accentColor, lineWidth: isLeader ? 2.5 : 1.5)
        )
        .shadow(radius: 3, y: 1)
        .onTapGesture { onTap() }
    }

    private var expandedCard: some View {
        // 优先级：权限请求 > 结构化 AskUserQuestion > 早期 fire-and-forget pendingQuestion > 普通输入。
        // 同时只能渲染一种主体内容。
        Group {
            if bubble.pendingPermission != nil {
                permissionCard
            } else if bubble.pendingAskUser != nil {
                elicitationCard
            } else if bubble.pendingQuestion != nil {
                askUserCard
            } else {
                defaultCard
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(bubble.state.accentColor, lineWidth: 2)
        )
        .shadow(radius: 8, y: 4)
    }

    /// 权限请求卡片（PermissionRequest hook 触发）。
    private var permissionCard: some View {
        let pp = bubble.pendingPermission!
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🔐 请求权限：\(pp.toolName)")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: { onResolvePermission("ask") }) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("交还终端处理")
            }
            if let cmd = pp.command {
                Text(cmd)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12))
                    )
            } else if let fp = pp.filePath {
                Text("📄 \(fp)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Button("拒绝") { onResolvePermission("deny") }
                    .buttonStyle(.bordered)
                    .tint(.red)
                Spacer()
                Button("交给终端") { onResolvePermission("ask") }
                    .buttonStyle(.bordered)
                Button("允许") { onResolvePermission("allow") }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
        .padding(12)
        .frame(width: 360, height: 160)
    }

    /// 结构化 AskUserQuestion 卡片：用户答完后通过挂起的 socket 同步回写 updatedInput.answers。
    /// 多问题时分页填写，最后一页提交时一次性回包。这条路径跨所有终端宿主工作（协议级而非系统级）。
    private var elicitationCard: some View {
        let pa = bubble.pendingAskUser!
        let total = max(1, pa.questions.count)
        let idx = min(elicitationIndex, total - 1)
        let current: AskUserQuestionItem? = pa.questions.indices.contains(idx) ? pa.questions[idx] : nil

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(total > 1 ? "❓ 在等你回答（\(idx + 1)/\(total)）" : "❓ 在等你回答")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: {
                    onResolveAskUser([:], true)  // cancel
                }) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("交还终端处理")
            }

            if let q = current {
                Text(q.question)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(4)

                if let opts = q.options, !opts.isEmpty {
                    // 选项：点击即填入答案。多选先简化为"点哪个就提交哪个"，与单选一致。
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(opts, id: \.self) { opt in
                            Button(action: {
                                elicitationAnswers[q.question] = opt
                                advanceOrSubmit(pa: pa)
                            }) {
                                HStack {
                                    Text(opt)
                                        .font(.system(size: 11))
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.12))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField("自定义回答…", text: bindingForAnswer(of: q.question), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit { advanceOrSubmit(pa: pa) }
            }

            HStack {
                if idx > 0 {
                    Button("上一题") { elicitationIndex = idx - 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(idx < total - 1 ? "下一题" : "发送") {
                    advanceOrSubmit(pa: pa)
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled((elicitationAnswers[current?.question ?? ""] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 360, height: 220)
        .onAppear { inputFocused = true }
    }

    private func bindingForAnswer(of question: String) -> Binding<String> {
        Binding(
            get: { elicitationAnswers[question] ?? "" },
            set: { elicitationAnswers[question] = $0 }
        )
    }

    private func advanceOrSubmit(pa: PendingAskUser) {
        let total = pa.questions.count
        let idx = min(elicitationIndex, max(0, total - 1))
        let q = pa.questions.indices.contains(idx) ? pa.questions[idx] : nil
        if let q {
            let cur = (elicitationAnswers[q.question] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cur.isEmpty else { return }
        }
        if idx < total - 1 {
            elicitationIndex = idx + 1
            return
        }
        // 提交：把已收集的 answers 全部 trim 后回写。
        let trimmed = elicitationAnswers.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.value.isEmpty }
        onResolveAskUser(trimmed, false)
        elicitationAnswers.removeAll()
        elicitationIndex = 0
    }

    /// 旧 fire-and-forget pendingQuestion 卡片（PreToolUse `tool_name=AskUserQuestion` 路径）。
    /// 这条路径没带 requestId，无法同步回包，只能展示提示让用户回到原终端作答。
    /// 新版本若 PermissionRequest 同步路径触发，会优先走 elicitationCard。
    private var askUserCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("❓ 在等你回答")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if let q = bubble.pendingQuestion {
                Text(q)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }
            Text("请到原终端 / Claude UI 回答。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 320, height: 130)
    }

    /// 默认卡片：只读的 session 状态摘要。气泡不再做"自由输入消息"入口。
    private var defaultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(bubble.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text("📁 \(bubble.displayCwd)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(bubble.state.badgeText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(bubble.state.accentColor)
                Spacer()
                Text("⏱ \(elapsed)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 280, height: 80)
    }
}
