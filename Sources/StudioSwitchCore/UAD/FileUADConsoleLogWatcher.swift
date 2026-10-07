import Foundation

public struct UADConsoleLogMark {
    let file: URL?
    let offset: UInt64
}

public protocol UADConsoleLogWatching {
    /// Where UAD Console's log currently ends, so only lines written afterwards are considered.
    func mark() -> UADConsoleLogMark
    /// Polls until a line containing `text` is written after `mark`, or `timeout` runs out.
    func waitForLine(containing text: String, after mark: UADConsoleLogMark, timeout: TimeInterval) -> Bool
}

/// Reads UAD Console's own log (`~/Library/Logs/Universal Audio/UAD Console_<date>.txt`, one file
/// per launch). It's the only reliable sign that a session finished loading: the window title read
/// through System Events can stay stale (seen 2026-10-07 after a reboot — "empty home" was loaded
/// while the title still said "home guit vox*"), whereas each load logs
/// `ReloadEngine … Show Progress Dialog` then `… Hide Progress Dialog`.
public final class FileUADConsoleLogWatcher: UADConsoleLogWatching {
    public static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Universal Audio")
    private static let pollInterval: TimeInterval = 0.25

    private let directory: URL
    private let sleep: (TimeInterval) -> Void

    public init(directory: URL = FileUADConsoleLogWatcher.defaultDirectory, sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.directory = directory
        self.sleep = sleep
    }

    public func mark() -> UADConsoleLogMark {
        guard let file = newestLog() else { return UADConsoleLogMark(file: nil, offset: 0) }
        return UADConsoleLogMark(file: file, offset: size(of: file))
    }

    public func waitForLine(containing text: String, after mark: UADConsoleLogMark, timeout: TimeInterval) -> Bool {
        var waited: TimeInterval = 0
        while true {
            if let file = newestLog() {
                // A log that isn't the marked one was started after the mark: read it whole.
                let offset = file == mark.file ? mark.offset : 0
                if newText(in: file, from: offset).contains(text) { return true }
            }
            guard waited < timeout else { return false }
            sleep(Self.pollInterval)
            waited += Self.pollInterval
        }
    }

    private func newestLog() -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("UAD Console_") && $0.pathExtension == "txt" }
            .max { modificationDate($0) < modificationDate($1) }
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private func size(of url: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func newText(in url: URL, from offset: UInt64) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
