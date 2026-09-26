public enum HealthStatus: Equatable {
    case ok
    case warning(String)
    case error(String)
}

public struct HealthCheckResult: Equatable, Identifiable {
    public var id: String { label }
    public let label: String
    public let status: HealthStatus
    /// Supplementary detail shown regardless of status — e.g. per-device wattage for a check
    /// that's green but still has something worth surfacing. Distinct from the message carried by
    /// `.warning`/`.error`, which explains *why* the status isn't ok.
    public let info: String?

    public init(label: String, status: HealthStatus, info: String? = nil) {
        self.label = label
        self.status = status
        self.info = info
    }
}
