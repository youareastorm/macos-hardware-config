import AppKit

public protocol RunningApplicationChecking {
    func isRunning(bundleID: String) -> Bool
}

public final class WorkspaceRunningApplicationChecker: RunningApplicationChecking {
    public init() {}

    public func isRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }
}
