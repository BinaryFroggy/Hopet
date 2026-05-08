import Foundation
import Darwin

/// 监听 ~/.hopet/run/hopetd.sock 的 Unix Domain Socket 服务端。
/// 用 BSD socket API 直接实现，避免 Network.framework 在 Unix path 上的兼容性问题。
///
/// 协议：每个 client 连接发一个长度前缀 JSON 帧；服务端可以选择性地回写一帧响应（permission_ask 走这条），
/// 然后关闭连接。fire-and-forget 的事件，上层 channel.reply(nil) 即关闭。
///
/// 同步请求（permission_ask）路径下，上层在收到帧后挂起 channel 等用户决策；如果对端进程
/// （hopet-emit）在用户作答前先死了（典型场景：用户在 cc 终端 deny ⇒ cc 直接 kill emit），
/// channel 会触发 `onPeerDisconnect` 注册的回调，让上层主动清理 UI 上的待决策气泡，
/// 避免"对端已关，气泡却还在"的躺尸。
public final class SocketServer {
    public typealias FrameHandler = @Sendable (Data, ClientChannel) -> Void

    /// 单次连接的双向通道。reply 与 onPeerDisconnect 互斥触发一次（先到者胜出），
    /// 都会负责关 fd；调用顺序无关。
    public final class ClientChannel: @unchecked Sendable {
        private let lock = NSLock()
        private let monitorQueue: DispatchQueue
        private var fd: Int32
        private var fired = false
        private var disconnectSource: DispatchSourceRead?
        private var disconnectHandler: (@Sendable () -> Void)?

        fileprivate init(fd: Int32, monitorQueue: DispatchQueue) {
            self.fd = fd
            self.monitorQueue = monitorQueue
        }

        /// 上层做决策后回包：data 非 nil 即写一帧响应，nil 表示无回包但请关闭连接。
        public func reply(_ data: Data?) {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            disconnectHandler = nil
            let source = disconnectSource
            disconnectSource = nil
            let localFd = fd
            fd = -1
            lock.unlock()

            source?.cancel()
            if let data {
                let resp = FrameCodec.encode(data)
                resp.withUnsafeBytes { raw in
                    var sent = 0
                    while sent < resp.count {
                        let r = write(localFd, raw.baseAddress!.advanced(by: sent), resp.count - sent)
                        if r <= 0 { break }
                        sent += r
                    }
                }
            }
            close(localFd)
        }

        /// 注册对端 EOF/HUP 时的清理回调，并立即起 DispatchSource 监听 fd。
        /// 重要：必须在这里同步 attach source，不能在 onFrame 后由 caller 单独 attach ——
        /// 上层 onFrame 通常会 `Task { @MainActor in ... }` 异步调度到主 actor，
        /// 当 source 已 resume 但 handler 尚未注册时 EOF 触发会丢事件，UI 留躺尸气泡。
        /// reply 已 fire 时 early-return；首次调本函数时同步建源，DispatchSource 在 resume
        /// 时会把已发生的 EOF 立刻投递出来。
        public func onPeerDisconnect(_ handler: @escaping @Sendable () -> Void) {
            lock.lock()
            if fired { lock.unlock(); return }
            disconnectHandler = handler
            let needsSource = (disconnectSource == nil) && (fd >= 0)
            let localFd = fd
            var newSource: DispatchSourceRead? = nil
            if needsSource {
                newSource = DispatchSource.makeReadSource(fileDescriptor: localFd, queue: monitorQueue)
                disconnectSource = newSource
            }
            lock.unlock()

            guard let source = newSource else { return }
            source.setEventHandler { [weak self] in
                guard let self else { return }
                // 探一字节判定是真有数据还是 EOF。本协议下 client 发完一帧后就只等响应，
                // 不会再写——所以 read > 0 也是异常情况，按 EOF 处理同样安全。
                var byte: UInt8 = 0
                let n = read(localFd, &byte, 1)
                if n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
                    self.fireDisconnect()
                }
            }
            source.resume()
        }

        private func fireDisconnect() {
            lock.lock()
            if fired { lock.unlock(); return }
            fired = true
            let handler = disconnectHandler
            disconnectHandler = nil
            let source = disconnectSource
            disconnectSource = nil
            let localFd = fd
            fd = -1
            lock.unlock()

            source?.cancel()
            if localFd >= 0 { close(localFd) }
            handler?()
        }
    }

    private let queue = DispatchQueue(label: "com.hopet.socket-server", qos: .userInitiated)
    private let acceptQueue = DispatchQueue(label: "com.hopet.socket-accept")
    private var listenFd: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let onFrame: FrameHandler

    public init(onFrame: @escaping FrameHandler) {
        self.onFrame = onFrame
    }

    public func start() throws {
        try HopetPaths.ensureDirectories()
        let socketURL = HopetPaths.socket
        let path = socketURL.path

        try? FileManager.default.removeItem(atPath: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "Hopet.SocketServer", code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "socket() failed: \(String(cString: strerror(errno)))"])
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw NSError(domain: "Hopet.SocketServer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "socket path too long: \(path)"])
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { cptr in
                for (i, b) in pathBytes.enumerated() { cptr[i] = CChar(bitPattern: b) }
                cptr[pathBytes.count] = 0
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let err = errno
            close(fd)
            throw NSError(domain: "Hopet.SocketServer", code: Int(err),
                          userInfo: [NSLocalizedDescriptionKey: "bind() failed: \(String(cString: strerror(err)))"])
        }

        chmod(path, 0o600)

        guard listen(fd, 32) == 0 else {
            let err = errno
            close(fd)
            throw NSError(domain: "Hopet.SocketServer", code: Int(err),
                          userInfo: [NSLocalizedDescriptionKey: "listen() failed: \(String(cString: strerror(err)))"])
        }

        listenFd = fd
        startAcceptLoop()
        HopetLog.info("socket server listening at \(path)")
        HopetLog.trace("socket listening at \(path)")
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFd >= 0 { close(listenFd); listenFd = -1 }
        try? FileManager.default.removeItem(at: HopetPaths.socket)
    }

    // MARK: -

    private func startAcceptLoop() {
        let fd = listenFd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            while true {
                var clientAddr = sockaddr()
                var len = socklen_t(MemoryLayout<sockaddr>.size)
                let client = accept(fd, &clientAddr, &len)
                if client < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK { break }
                    break
                }
                self.handle(client: client)
            }
        }
        source.resume()
        acceptSource = source
    }

    private func handle(client fd: Int32) {
        // 屏蔽 SIGPIPE：对端 hopet-emit 被宿主 kill（用户在 cc 终端 deny）后，
        // socket 进入 close-wait；此后用户在 Hopet 气泡上做决策走到 write(fd, ...) 时，
        // 内核会同时返回 EPIPE 并向进程投 SIGPIPE。Hopet 无 GUI 进程默认 SIGPIPE handler
        // ⇒ 直接被信号杀死。SO_NOSIGPIPE 让此 fd 上的 write 仅返回 EPIPE，由调用方静默忽略。
        var noSigpipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE,
                       &noSigpipe, socklen_t(MemoryLayout<Int32>.size))

        let onFrame = self.onFrame
        queue.async {
            // 读到第一个完整帧。
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 16 * 1024)
            var firstFrame: Data?
            while true {
                let n = chunk.withUnsafeMutableBufferPointer { ptr -> Int in
                    read(fd, ptr.baseAddress, ptr.count)
                }
                if n <= 0 { break }
                buffer.append(chunk, count: n)
                let (frames, leftover) = FrameCodec.decode(buffer: buffer)
                buffer = leftover
                if let f = frames.first {
                    firstFrame = f
                    break
                }
            }

            guard let frame = firstFrame else {
                close(fd)
                return
            }

            let channel = ClientChannel(fd: fd, monitorQueue: self.queue)
            // 不再设兜底超时：用户可能很久才在气泡上做决策，本地超时只会让按钮变成"假活"。
            // 异常退出场景靠上层在 onPeerDisconnect 注册时 lazy attach 的 source 触发清理；
            // 最坏情况下进程结束自动回收 fd。
            onFrame(frame, channel)
        }
    }
}
