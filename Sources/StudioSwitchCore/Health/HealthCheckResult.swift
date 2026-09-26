public enum HealthStatus: Equatable {
    case ok
    case warning(String)
    case error(String)
}

public struct HealthCheckResult: Equatable, Identifiable {
    public var id: String { label }
    public let label: String
    public let status: HealthStatus

    public init(label: String, status: HealthStatus) {
        self.label = label
        self.status = status
    }
}
