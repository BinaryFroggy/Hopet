import Foundation

public enum HookDoctor {
    public static func run(installer: HookInstaller) -> String {
        var lines: [String] = []
        lines.append("=== Hopet Doctor ===")

        // Paths
        lines.append("home dir: \(HopetPaths.home.path)")
        for url in [HopetPaths.bin, HopetPaths.run, HopetPaths.state, HopetPaths.themes, HopetPaths.logs] {
            let exists = FileManager.default.fileExists(atPath: url.path)
            lines.append("\(exists ? "✓" : "✗") \(url.path)")
        }

        // Socket
        let sockExists = FileManager.default.fileExists(atPath: HopetPaths.socket.path)
        lines.append("\(sockExists ? "✓" : "✗") socket: \(HopetPaths.socket.path)")

        // Emit binary
        let emitExists = FileManager.default.fileExists(atPath: HopetPaths.emitBinary.path)
        lines.append("\(emitExists ? "✓" : "✗") hopet-emit: \(HopetPaths.emitBinary.path)")

        // Tools —— 遍历 recognized，新增工具自动覆盖，避免漏登记。
        for tool in AITool.recognized {
            lines.append("\(tool.displayName) hooks installed: \(installer.isInstalled(tool) ? "yes" : "no")")
        }

        return lines.joined(separator: "\n")
    }
}
