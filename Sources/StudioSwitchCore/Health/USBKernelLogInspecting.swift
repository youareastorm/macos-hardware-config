import Foundation

public protocol USBKernelLogInspecting {
    /// Raw USB/IOKit kernel log lines from the last `window` seconds, oldest first — the same
    /// events Console.app's "USB" filter shows, since both read the unified log. A snapshot query
    /// (`system_profiler`, `ioreg`) only sees the *current* negotiated state, so it misses a hub
    /// that briefly lost power and recovered, or a drive cycling on and off — this reads the
    /// event trail instead.
    func recentUSBKernelEvents(within window: TimeInterval) -> [String]
}
