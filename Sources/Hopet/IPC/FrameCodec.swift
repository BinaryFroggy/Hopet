import Foundation

/// 长度前缀（UInt32 BE）+ JSON payload 的编解码（架构文档 §8.2）。
public enum FrameCodec {
    public static let maxPayloadBytes: Int = 1 * 1024 * 1024 // 1 MB 安全上限

    public static func encode(_ payload: Data) -> Data {
        precondition(payload.count <= UInt32.max)
        var lengthBE = UInt32(payload.count).bigEndian
        var data = Data(bytes: &lengthBE, count: MemoryLayout<UInt32>.size)
        data.append(payload)
        return data
    }

    /// 流式解码：从可累积 buffer 中弹出尽可能多的完整帧。
    /// 返回 (frames, remainingBuffer)。
    public static func decode(buffer: Data) -> ([Data], Data) {
        var cursor = 0
        var frames: [Data] = []
        while buffer.count - cursor >= 4 {
            let lengthSlice = buffer[(buffer.startIndex + cursor)..<(buffer.startIndex + cursor + 4)]
            let length = lengthSlice.withUnsafeBytes { raw -> UInt32 in
                raw.load(as: UInt32.self).bigEndian
            }
            guard length <= maxPayloadBytes else {
                // 帧过大 → 丢弃整个 buffer
                return ([], Data())
            }
            let need = Int(length)
            if buffer.count - cursor - 4 < need { break }
            let start = buffer.startIndex + cursor + 4
            let end   = start + need
            frames.append(buffer[start..<end])
            cursor += 4 + need
        }
        return (frames, buffer.subdata(in: (buffer.startIndex + cursor)..<buffer.endIndex))
    }
}
