import Foundation

/// Runs `log show` (the same unified log Console.app reads) filtered to USB/IOKit activity.
/// Kernel-emitted messages usually carry no `subsystem`, so the predicate also matches on
/// `process == "kernel"` with "usb" in the free-text message, not just a subsystem name.
public final class LogShowUSBKernelLogInspector: USBKernelLogInspecting {
    public init() {}

    public func recentUSBKernelEvents(within window: TimeInterval) -> [String] {
        let minutes = max(1, Int(window / 60))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--last", "\(minutes)m",
            "--style", "compact",
            "--predicate", "(subsystem CONTAINS[c] \"usb\") OR (process == \"kernel\" AND eventMessage CONTAINS[c] \"usb\")"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output
            .components(separatedBy: .newlines)
            .filter { line in
                // `log show` prints a couple of header lines before the actual entries.
                !line.isEmpty && !line.hasPrefix("Filtering the log data") && !line.hasPrefix("Timestamp")
            }
    }
}
