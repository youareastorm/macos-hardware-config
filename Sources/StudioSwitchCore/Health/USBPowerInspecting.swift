public protocol USBPowerInspecting {
    /// Names of connected USB devices (hubs included) currently drawing more current than their
    /// port can supply — the classic symptom of an unpowered/underpowered hub.
    func underpoweredDeviceNames() -> [String]
}
