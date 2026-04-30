import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// MARK: - Output

func eprint(_ msg: String) {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
}

// MARK: - Args

struct Args {
    var tool: String?
    var event: String?
    var requires: [(path: String, value: String)] = []
    var excludes: [(path: String, value: String)] = []
    var sessionIdOverride: String?
    var help: Bool = false
}

func parseArgs(_ argv: [String]) -> Args {
    var args = Args()
    var i = 1
    while i < argv.count {
        let a = argv[i]
        switch a {
        case "--tool":
            i += 1
            if i < argv.count { args.tool = argv[i] }
        case "--event":
            i += 1
            if i < argv.count { args.event = argv[i] }
        case "--require":
            i += 1
            if i < argv.count, let pair = parsePair(argv[i]) { args.requires.append(pair) }
        case "--exclude":
            i += 1
            if i < argv.count, let pair = parsePair(argv[i]) { args.excludes.append(pair) }
        case "--session-id":
            i += 1
            if i < argv.count { args.sessionIdOverride = argv[i] }
        case "-h", "--help":
            args.help = true
        default:
            break
        }
        i += 1
    }
    return args
}

func parsePair(_ s: String) -> (String, String)? {
    guard let eq = s.firstIndex(of: "=") else { return nil }
    let k = String(s[s.startIndex..<eq])
    let v = String(s[s.index(after: eq)...])
    return (k, v)
}

let args = parseArgs(CommandLine.arguments)

if args.help {
    let text = """
    Usage: hopet-emit --tool <claude-code|codex|custom> --event <kind>
                       [--require <field>=<value>] [--exclude <field>=<value>]
                       [--session-id <id>]
                       < hook_payload.json

    Reads a hook payload from stdin and dispatches a normalized StateEvent
    to ~/.hopet/run/hopetd.sock as a length-prefixed JSON frame.

    On any failure (socket missing, write error, invalid input, filter mismatch),
    exits 0 silently to avoid blocking the parent AI hook.
    """
    print(text)
    exit(0)
}

guard let toolRaw = args.tool, let eventRaw = args.event else {
    eprint("hopet-emit: missing --tool or --event"); exit(0)
}

// MARK: - Read stdin (hook payload)

// 必须用 readDataToEndOfFile 阻塞等到 cc close stdin —— availableData 是非阻塞的，
// 在 cc fork+pipe 还没写完 payload 时就会返回空 Data，导致下游 session_id 兜底成
// `anon-XXXX`、payload 为空。Hopet 侧 EventRouter 把 `anon-` 前缀直接当 subagent 丢，
// 配对的 PostToolUse 因此永远不到 cancelPending，权限气泡卡死、宠物状态不切。
let stdin = FileHandle.standardInput
let stdinData = stdin.readDataToEndOfFile()
let hookJson: [String: Any]
if stdinData.isEmpty {
    hookJson = [:]
} else if let obj = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any] {
    hookJson = obj
} else {
    hookJson = [:]
}

// MARK: - Field path lookup (dotted path)

func value(at path: String, in dict: [String: Any]) -> Any? {
    let parts = path.split(separator: ".").map(String.init)
    var cursor: Any = dict
    for part in parts {
        guard let map = cursor as? [String: Any], let next = map[part] else { return nil }
        cursor = next
    }
    return cursor
}

func stringify(_ any: Any?) -> String? {
    guard let any else { return nil }
    if let s = any as? String { return s }
    if let n = any as? NSNumber { return n.stringValue }
    if let b = any as? Bool { return b ? "true" : "false" }
    return nil
}

// --require / --exclude
for (k, v) in args.requires {
    guard stringify(value(at: k, in: hookJson)) == v else { exit(0) }
}
for (k, v) in args.excludes {
    if stringify(value(at: k, in: hookJson)) == v { exit(0) }
}

// MARK: - Build StateEvent payload (whitelist fields only)

let allowedKeys: [String] = [
    "tool_name",
    "tool_input",                   // AskUserQuestion 时整块原 tool_input 留下，气泡侧需要 questions 列表
    "tool_input.command",
    "tool_input.file_path",
    "tool_input.question",
    // UserPromptSubmit hook 的 prompt：Hopet 用它生成会话标题。
    // 不加进白名单的话气泡会一直回退到 cwd 当标题。
    "prompt",
    "notification_type",
    "message",
    "session_id",
    "cwd",
    // 子 agent 识别字段（Task 工具触发的子上下文）。
    // Claude Code 不同版本暴露的字段名不一致，全部拉上来由 Hopet 侧做识别。
    "parent_session_id",
    "agent_id",
    "agent_type",
    "subagent_id",
    "subagent_type",
    "transcript_path",
    "source"
]

var safePayload: [String: Any] = [:]
for path in allowedKeys {
    if var v = value(at: path, in: hookJson) {
        if let s = v as? String, s.count > 256 {
            v = String(s.prefix(256))
        }
        safePayload[path] = v
    }
}

// session_id 解析顺序：override > stdin.session_id > random
let sessionId: String = args.sessionIdOverride
    ?? (stringify(value(at: "session_id", in: hookJson)))
    ?? "anon-\(UUID().uuidString.prefix(8))"

let cwd: String? = stringify(value(at: "cwd", in: hookJson))

// 终端身份信息：让 Hopet 之后能反查到是哪个 Terminal/iTerm 标签页。
// 取自 hook 进程继承的环境变量 + 沿 ppid 链查 tty。
let env = ProcessInfo.processInfo.environment
let termProgram = env["TERM_PROGRAM"]
// Apple Terminal 用 TERM_SESSION_ID，iTerm2 用 ITERM_SESSION_ID。
let termSessionEnvId = env["ITERM_SESSION_ID"] ?? env["TERM_SESSION_ID"]

// tty: 先试 stderr/stdout/stdin（hook 通常 stdin 是 pipe，但 stderr 大概率连着 Terminal pty）。
// 失败再走 ps 逐级 ppid 找。
func ttyOfFd(_ fd: Int32) -> String? {
    guard isatty(fd) != 0 else { return nil }
    guard let cstr = ttyname(fd) else { return nil }
    return String(cString: cstr)
}
var psTrace: [String] = []
func ttyViaPsChain() -> String? {
    var pid = getppid()
    var hops = 0
    while pid > 1, hops < 12 {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-o", "tty=,ppid=,comm=", "-p", "\(pid)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch {
            psTrace.append("hop\(hops) pid=\(pid) launch failed: \(error)")
            return nil
        }
        task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        psTrace.append("hop\(hops) pid=\(pid) raw=\"\(trimmed)\"")
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count >= 2 else { return nil }
        let tty = parts[0]
        if tty != "??" && !tty.isEmpty {
            return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        }
        guard let nextPid = pid_t(parts[1]) else { return nil }
        pid = nextPid
        hops += 1
    }
    return nil
}
let tty = ttyOfFd(STDERR_FILENO)
       ?? ttyOfFd(STDOUT_FILENO)
       ?? ttyOfFd(STDIN_FILENO)
       ?? ttyViaPsChain()

// permission_ask 走双向请求-响应路径，需要 requestId。
let needsResponse = (eventRaw == "permission_ask")
let requestId: String? = needsResponse ? UUID().uuidString : nil

// 子 agent 识别：任一识别字段有值就标记为 subagent，让 Hopet 侧丢弃。
// 注：transcript_path 主线 agent 也会有，不能单独作判据。
let subagentSignals = ["parent_session_id", "agent_id", "subagent_id", "subagent_type", "agent_type"]
let isSubagent = subagentSignals.contains { key in
    if let v = stringify(value(at: key, in: hookJson)), !v.isEmpty { return true }
    return false
}

// 顶层 envelope
var envelope: [String: Any] = [
    "schema": 1,
    "sessionId": sessionId,
    "tool": toolRaw,
    "event": eventRaw,
    "timestamp": ISO8601DateFormatter().string(from: Date())
]
if let cwd { envelope["cwd"] = cwd }
if let termProgram { envelope["terminalApp"] = termProgram }
if let tty { envelope["terminalTty"] = tty }
if let termSessionEnvId { envelope["terminalSessionId"] = termSessionEnvId }
if !safePayload.isEmpty { envelope["payload"] = safePayload }
if let requestId { envelope["requestId"] = requestId }
if isSubagent { envelope["isSubagent"] = true }

guard let envelopeData = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]) else {
    exit(0)
}

// 调试落盘：每次 emit 的 envelope 追加到 ~/.hopet/logs/emit-debug.log，便于在 hook 不可见 stderr 的环境下排查。
do {
    let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    let logDir = home + "/.hopet/logs"
    try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    let logPath = logDir + "/emit-debug.log"
    let stamp = ISO8601DateFormatter().string(from: Date())
    var line = "\(stamp)  ttyDetect: stderrIsTTY=\(isatty(STDERR_FILENO)) stdoutIsTTY=\(isatty(STDOUT_FILENO)) stdinIsTTY=\(isatty(STDIN_FILENO)) tty=\(tty ?? "nil") termProgram=\(termProgram ?? "nil") termSessionEnvId=\(termSessionEnvId ?? "nil")\n"
    let envKeys = ["TERM_PROGRAM", "TERM_SESSION_ID", "ITERM_SESSION_ID", "TERM", "TTY",
                   "WINDOWID", "ALACRITTY_LOG", "WEZTERM_PANE", "VSCODE_INJECTION",
                   "LC_TERMINAL", "LC_TERMINAL_VERSION",
                   "SHELL", "USER", "HOME", "PATH"]
    var envSnapshot: [String] = []
    for k in envKeys {
        if let v = env[k] { envSnapshot.append("\(k)=\(v)") }
    }
    line += "  env: \(envSnapshot.joined(separator: " | "))\n"
    line += "  psChain:\n"
    for entry in psTrace {
        line += "    \(entry)\n"
    }
    line += "  envelope: " + (String(data: envelopeData, encoding: .utf8) ?? "<bin>") + "\n"
    if let data = line.data(using: .utf8) {
        if let fh = FileHandle(forWritingAtPath: logPath) {
            try? fh.seekToEnd()
            fh.write(data)
            try? fh.close()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }
}

// MARK: - Send via Unix Domain Socket

let socketPath: String = {
    let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    return home + "/.hopet/run/hopetd.sock"
}()

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
defer { close(fd) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { exit(0) }
withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
    ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { cptr in
        for (idx, b) in pathBytes.enumerated() {
            cptr[idx] = CChar(bitPattern: b)
        }
        cptr[pathBytes.count] = 0
    }
}

let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
        connect(fd, sa, addrLen)
    }
}
guard connectResult == 0 else { exit(0) }

// 长度前缀帧（UInt32 BE）+ JSON
var lengthBE = UInt32(envelopeData.count).bigEndian
let header = Data(bytes: &lengthBE, count: MemoryLayout<UInt32>.size)
var frame = Data()
frame.append(header)
frame.append(envelopeData)

frame.withUnsafeBytes { raw in
    var sent = 0
    while sent < frame.count {
        let result = write(fd, raw.baseAddress!.advanced(by: sent), frame.count - sent)
        if result <= 0 { break }
        sent += result
    }
}

// 非 permission_ask：fire-and-forget，立刻退出。
guard needsResponse else { exit(0) }

// permission_ask 路径：阻塞等 Hopet 的决策，没有本地超时 ——
// 用户可能去做别的事很久才回来点气泡，超时只会徒增"假活按钮"的体验。
// Hopet 进程退出时 socket 关闭，下面的 read 会读到 EOF / 错误后由 emitDecision(nil)
// 兜底输出 `{}` 让 Claude 走自身 UI。

func recvAll(_ fd: Int32, count: Int) -> Data? {
    var buf = [UInt8](repeating: 0, count: count)
    var got = 0
    while got < count {
        let n = buf.withUnsafeMutableBufferPointer { ptr -> Int in
            read(fd, ptr.baseAddress!.advanced(by: got), count - got)
        }
        if n <= 0 { return nil }
        got += n
    }
    return Data(buf)
}

/// 输出 Claude PermissionRequest 期望的 hookSpecificOutput JSON 到 stdout。
///
/// - 普通权限：decision = "allow" | "deny"，可附 reason（仅 deny 走 message）。
/// - AskUserQuestion 应答：decision = "allow" 且带 updatedInput，hookSpecificOutput.decision
///   形如 `{ behavior: "allow", updatedInput: { ...原 tool_input, answers: { 问题: 答案 } } }`。
/// - 其它情况（ask / 超时 / 解析失败）：输出 {} 让 Claude 自走默认 UI。
func emitDecision(_ decision: String?, reason: String? = nil, updatedInput: Any? = nil) -> Never {
    guard let decision, decision == "allow" || decision == "deny" else {
        FileHandle.standardOutput.write(Data("{}".utf8))
        exit(0)
    }
    var decisionDict: [String: Any] = ["behavior": decision]
    if let reason, decision == "deny" { decisionDict["message"] = reason }
    if let updatedInput, decision == "allow" { decisionDict["updatedInput"] = updatedInput }
    let hookSpecific: [String: Any] = [
        "hookEventName": "PermissionRequest",
        "decision": decisionDict
    ]
    let payload: [String: Any] = ["hookSpecificOutput": hookSpecific]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data)
    }
    exit(0)
}

guard let lengthBuf = recvAll(fd, count: 4) else { emitDecision(nil) }
let respLen = lengthBuf.withUnsafeBytes { raw -> UInt32 in
    raw.load(as: UInt32.self).bigEndian
}
guard respLen > 0, respLen < 1_000_000 else { emitDecision(nil) }
guard let body = recvAll(fd, count: Int(respLen)),
      let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      let decision = obj["decision"] as? String else {
    emitDecision(nil)
}
emitDecision(
    decision,
    reason: obj["reason"] as? String,
    updatedInput: obj["updatedInput"]
)
