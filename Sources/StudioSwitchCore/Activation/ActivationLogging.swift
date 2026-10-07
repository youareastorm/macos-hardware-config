import Foundation

/// A line-per-event record of what automatic and manual activations found and did, so a startup
/// or a plug-in can be analyzed afterwards instead of guessed from system logs.
public protocol ActivationLogging {
    func log(_ message: String)
}

public struct NoActivationLogger: ActivationLogging {
    public init() {}
    public func log(_ message: String) {}
}

/// Appends to `~/Library/Logs/StudioSwitch/activation.log` by default (readable in Console.app),
/// prefixing each line with a local timestamp to the millisecond. When the file grows past
/// `maxBytes` it's moved to `activation.log.1` and a new one is started, so it never grows unbounded.
public final class FileActivationLogger: ActivationLogging {
    /// One instance for the whole app, so automatic and manual activations write through the same
    /// queue and their lines never interleave.
    public static let shared = FileActivationLogger()

    public static let defaultFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/StudioSwitch/activation.log")

    private let fileURL: URL
    private let maxBytes: Int
    private let now: () -> Date
    private let formatter: DateFormatter
    private let queue = DispatchQueue(label: "com.simonrenard.studioswitch.activationlog")

    public init(fileURL: URL = FileActivationLogger.defaultFileURL, maxBytes: Int = 1_000_000, now: @escaping () -> Date = Date.init, timeZone: TimeZone = .current) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.now = now
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    public func log(_ message: String) {
        let line = "\(formatter.string(from: now()))  \(message)\n"
        queue.async { [fileURL, maxBytes] in
            let manager = FileManager.default
            try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? manager.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > maxBytes {
                let previous = URL(fileURLWithPath: fileURL.path + ".1")
                try? manager.removeItem(at: previous)
                try? manager.moveItem(at: fileURL, to: previous)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    /// Waits for pending lines to be written (for tests).
    func flush() {
        queue.sync {}
    }
}
