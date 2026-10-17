extension ProfileActivationResult {
    /// The device was found but at least one activation step reported an error.
    public var hasError: Bool {
        deviceDetected && [deviceConfigError, channelPairError, uadConsoleError, uadOfflineDevicesError, uadMixerError, uadConsoleWindowError]
            .contains { $0 != nil }
    }
}

/// Decides whether the menu-bar icon should show an alert, so a problem is visible without
/// opening the menu.
public enum StatusEvaluation {
    public static func needsAttention(health: [HealthCheckResult], lastActivation: ProfileActivationResult?) -> Bool {
        health.contains { $0.status != .ok } || lastActivation?.hasError == true
    }
}
