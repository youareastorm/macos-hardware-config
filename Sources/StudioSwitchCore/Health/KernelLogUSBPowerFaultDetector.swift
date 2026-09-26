import Foundation

public final class KernelLogUSBPowerFaultDetector: USBPowerFaultDetecting {
    /// Deliberately broad: catches explicit power wording as well as the reset/attach/detach
    /// churn a power-starved device produces even when no message ever says "power".
    static let keywords = [
        "power", "current", "over-current", "overcurrent", "insufficient",
        "enumerat", "reset", "fail", "detach", "terminat", "disconnect"
    ]

    private let logInspector: USBKernelLogInspecting

    public init(logInspector: USBKernelLogInspecting = LogShowUSBKernelLogInspector()) {
        self.logInspector = logInspector
    }

    public func recentPowerIncidents(within window: TimeInterval) -> [USBPowerIncident] {
        logInspector.recentUSBKernelEvents(within: window)
            .filter { line in
                let lowered = line.lowercased()
                return Self.keywords.contains { lowered.contains($0) }
            }
            .map(USBPowerIncident.init)
    }
}
