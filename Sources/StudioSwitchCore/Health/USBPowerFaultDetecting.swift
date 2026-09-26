public struct USBPowerIncident: Equatable {
    public let line: String

    public init(line: String) {
        self.line = line
    }
}

public protocol USBPowerFaultDetecting {
    /// Kernel log lines from the last `window` that look power-related (explicit power/current
    /// wording, or a reset/attach/detach cycle) — a heuristic first pass over the same evidence a
    /// person would eyeball in Console.app, not an authoritative per-device verdict.
    func recentPowerIncidents(within window: TimeInterval) -> [USBPowerIncident]
}
