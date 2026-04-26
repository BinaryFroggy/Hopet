import Foundation
import Darwin

/// 监听 ~/.hopet/run/hopetd.sock 的 Unix Domain Socket 服务端。
/// 用 BSD socket API 直接实现，避免 Network.framework 在 Unix path 上的兼容性问题。
///
/// 协议：每个 client 连接发一个长度前缀 JSON 帧；服务端可以选择性地回写一帧响应（permission_ask 走这条），
/// 然后关闭连接。fire-and-forget 的事件，上层 reply(nil) 即关闭。
public final class SocketServer {
    public typealias Reply = @Sendable (Data?) -> Void
    public typealias FrameHandler = @Sendable (Data, @escaping Reply) -> Void

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

            let didReply = ReplyGuard()
            let reply: Reply = { responseData in
                guard didReply.markIfFirst() else { return }
                if let responseData {
                    let resp = FrameCodec.encode(responseData)
                    resp.withUnsafeBytes { raw in
                        var sent = 0
                        while sent < resp.count {
                            let r = write(fd, raw.baseAddress!.advanced(by: sent), resp.count - sent)
                            if r <= 0 { break }
                            sent += r
                        }
                    }
                }
                close(fd)
            }
            onFrame(frame, reply)

            // 30s 超时兜底：上层若忘了 reply，强制关闭连接，避免泄漏 fd。
            self.queue.asyncAfter(deadline: .now() + 30) {
                reply(nil)
            }
        }
    }
}

/// 简单的 once-only 标志，保证 reply 只生效一次。
private final class ReplyGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func markIfFirst() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
