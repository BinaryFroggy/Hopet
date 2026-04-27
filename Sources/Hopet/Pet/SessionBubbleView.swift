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
    /// 折叠态用的紧凑耗时，例如 "5m" / "30s"。
    let elapsedShort: String
    /// 展开态用的描述：运行中显示"已运行 X"，闲置显示"X 前"。
    let stateDurationPhrase: String
    let onTap: () -> Void
    let onResolvePermission: (String) -> Void  // "allow" / "deny" / "ask"
    /// AskUserQuestion 答题提交回调。`answers` 形如 `{ "问题文案": "回答" }`；
    /// `cancel = true` 表示用户取消（让 Claude 走自身 UI）。
    let onResolveAskUser: ([String: String], Bool) -> Void
    let onDismiss: () -> Void

    public init(
        bubble: SessionBubble,
        isLeader: Bool,
        elapsedShort: String,
        stateDurationPhrase: String,
        onTap: @escaping () -> Void,
        onResolvePermission: @escaping (String) -> Void = { _ in },
        onResolveAskUser: @escaping ([String: String], Bool) -> Void = { _, _ in },
        onDismiss: @escaping () -> Void
    ) {
        self.bubble = bubble
        self.isLeader = isLeader
        self.elapsedShort = elapsedShort
        self.stateDurationPhrase = stateDurationPhrase
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
        ZStack {
            if bubble.expanded {
                expandedCard
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.35, anchor: .center).combined(with: .opacity),
                        removal: .scale(scale: 0.35, anchor: .center).combined(with: .opacity)
                    ))
            } else {
                collapsedDot
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6, anchor: .center).combined(with: .opacity),
                        removal: .scale(scale: 0.6, anchor: .center).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: bubble.expanded)
    }

    private var collapsedDot: some View {
        // 是否处于"运行中"状态：决定折叠态时间前缀图标。
        let isRunning: Bool = {
            switch bubble.state {
            case .thinking, .responding, .toolUse, .askUser, .permissionPrompt: return true
            case .idle, .completed, .errorInterrupted: return false
            }
        }()

        return VStack(spacing: 1) {
            Text(bubble.displayCwd)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .truncationMode(.middle)
            HStack(spacing: 2) {
                Image(systemName: isRunning ? "play.fill" : "clock")
                    .font(.system(size: 7))
                Text(elapsedShort)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .frame(width: 64, height: 64)
        .background(
            Circle().fill(.ultraThinMaterial)
        )
        .overlay(
            Circle().stroke(bubble.state.accentColor, lineWidth: isLeader ? 2.5 : 1.5)
        )
        .shadow(radius: 3, y: 1)
        .contentShape(Circle())
        .onTapGesture { onTap() }
    }

    @ViewBuilder
    private var expandedCard: some View {
        // 优先级：权限请求 > 结构化 AskUserQuestion > 早期 fire-and-forget pendingQuestion > 普通输入。
        // 同时只能渲染一种主体内容。
        if bubble.pendingPermission != nil {
            permissionCard.modifier(ExpandedCardChrome(accent: bubble.state.accentColor))
        } else if bubble.pendingAskUser != nil {
            elicitationCard.modifier(ExpandedCardChrome(accent: bubble.state.accentColor))
        } else if bubble.pendingQuestion != nil {
            askUserCard.modifier(ExpandedCardChrome(accent: bubble.state.accentColor))
        } else {
            // 普通态：横向不规则大气泡，整张卡可点击收起。
            defaultCard.modifier(IrregularBubbleChrome(accent: bubble.state.accentColor))
        }
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
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
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

    /// 默认卡片：横向不规则大气泡。展示目录、标题（若有）、状态持续时长。整张卡再点击一次收起。
    private var defaultCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(bubble.state.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                if bubble.hasTitle {
                    Text("📁 \(bubble.displayCwd)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(bubble.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // 没有真实标题：只渲染目录，不再补占位"标题"行，避免重复。
                    Text("📁 \(bubble.displayCwd)")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(bubble.state.badgeText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(bubble.state.accentColor)
                    .lineLimit(1)
                    .fixedSize()
                Text(stateDurationPhrase)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 360, alignment: .leading)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

/// 普通态使用的"横向不规则大气泡"外壳：四角不等的圆角矩形 + 半透明材质 + 状态色描边。
private struct IrregularBubbleChrome: ViewModifier {
    let accent: Color

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 28,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: 32,
            topTrailingRadius: 22,
            style: .continuous
        )
    }

    func body(content: Content) -> some View {
        content
            .background(shape.fill(.ultraThinMaterial))
            .overlay(shape.stroke(accent, lineWidth: 2))
            .shadow(radius: 8, y: 4)
    }
}

/// 决策类卡片（权限/AskUser/旧 fire-and-forget）沿用稳重的圆角矩形外壳。
private struct ExpandedCardChrome: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accent, lineWidth: 2)
            )
            .shadow(radius: 8, y: 4)
    }
}
