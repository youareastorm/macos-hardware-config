import Foundation

/// Checks USB health via `system_profiler`'s machine-readable JSON output.
///
/// Root cause of an earlier bug, found and fixed here: the data type is `SPUSBHostDataType` on
/// current macOS (confirmed on an Apple Silicon Mac running macOS Tahoe) — the older
/// `SPUSBDataType` name silently returns `{"SPUSBDataType": []}` (no error, exit code 0) instead
/// of failing, so a typo'd/renamed data type looks exactly like "nothing connected".
///
/// What this can't do, verified empirically rather than assumed: detecting a specific
/// *underpowered* device (e.g. a self-powered hub that lost its wall adapter). The older
/// `system_profiler` text output used to show paired "Current Available (mA)" / "Current
/// Required (mA)" fields; neither `SPUSBHostDataType`'s JSON (only `USBDeviceKeyPowerAllocation`,
/// what was granted — no "required" counterpart) nor `ioreg -p IOUSB` exposes that comparison on
/// this host stack. Unplugging a hub's wall adapter here, mid-session, produced zero observable
/// change in either — not a missing key we could add a lookup for, but a signal macOS genuinely
/// doesn't surface for this hardware. So this only reports whether USB enumeration itself is
/// healthy (system_profiler returning real data at all), not per-device power starvation.
public final class SystemProfilerUSBPowerProvider: USBPowerInspecting {
    private static let dataType = "SPUSBHostDataType"

    public init() {}

    public func checkPower() -> USBPowerCheckOutcome {
        guard let root = runSystemProfilerJSON(),
              let buses = root[Self.dataType] as? [[String: Any]],
              !buses.isEmpty else {
            return .unavailable
        }
        return .ok
    }

    private func runSystemProfilerJSON() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", Self.dataType]

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
}
