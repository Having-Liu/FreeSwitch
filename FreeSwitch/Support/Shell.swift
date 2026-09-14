import Foundation

/// 运行命令行工具与 AppleScript 的小工具（非沙盒环境）。
enum Shell {
    @discardableResult
    nonisolated static func run(_ launchPath: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "launch error: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// 执行 AppleScript，失败返回 nil 并记录日志。
    @discardableResult
    static func runAppleScript(_ source: String) -> String? {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("[FreeSwitch] AppleScript error: \(errorInfo)")
            return nil
        }
        return result.stringValue
    }
}
