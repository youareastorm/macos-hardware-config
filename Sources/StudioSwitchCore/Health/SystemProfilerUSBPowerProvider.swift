import Foundation

/// Detects underpowered USB devices (a hub not plugged into the wall, or a bus-powered drive
/// starved of current) via `system_profiler`'s machine-readable JSON output. JSON/XML keys are
/// used instead of the human-readable text output because `system_profiler`'s text labels are
/// localized to the system's language — hardcoding an English label like "Current Available
/// (mA)" would silently stop matching on a non-English Mac.
///
/// `system_profiler -json SPUSBDataType` has been observed to return a top-level empty array
/// (`{"SPUSBDataType": []}`, no error, exit code 0) on a real, fully-populated USB topology —
/// confirmed on an Apple Silicon Mac running macOS Tahoe, both with and without JSON output, in
/// both a sandboxed and a plain interactive shell. `ioreg -p IOUSB` sees the same devices fine,
/// so this isn't a permissions issue; it's `system_profiler` itself failing to enumerate. An empty
/// result therefore is NOT treated as "nothing underpowered" — that would silently hide a real
/// problem — it's reported as `.unavailable` so the health check can say "couldn't verify"
/// instead of a false "OK".
public final class SystemProfilerUSBPowerProvider: USBPowerInspecting {
    public init() {}

    public func checkPower() -> USBPowerCheckOutcome {
        guard let root = runSystemProfilerJSON(),
              let buses = root["SPUSBDataType"] as? [[String: Any]],
              !buses.isEmpty else {
            return .unavailable
        }

        var results: [String] = []
        for bus in buses {
            collectUnderpowered(from: bus, into: &results)
        }
        return results.isEmpty ? .ok : .underpowered(results)
    }

    private func runSystemProfilerJSON() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPUSBDataType"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func collectUnderpowered(from node: [String: Any], into results: inout [String]) {
        if let available = numericCurrent(in: node, matching: "available"),
           let required = numericCurrent(in: node, matching: "required"),
           required > available,
           let name = node["_name"] as? String {
            results.append(name)
        }

        if let children = node["_items"] as? [[String: Any]] {
            for child in children {
                collectUnderpowered(from: child, into: &results)
            }
        }
    }

    /// Looks up a "current ... <keyword>" field by key content rather than an exact literal key
    /// name, since the precise key `system_profiler -json` uses for these fields isn't
    /// consistently documented.
    private func numericCurrent(in node: [String: Any], matching keyword: String) -> Int? {
        for (key, value) in node {
            let lowercasedKey = key.lowercased()
            guard lowercasedKey.contains("current"), lowercasedKey.contains(keyword) else { continue }
            if let number = value as? Int { return number }
            if let string = value as? String { return Int(string) }
        }
        return nil
    }
}
