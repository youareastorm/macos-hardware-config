/// Outcome of a USB health check: whether `system_profiler` could enumerate USB devices at all,
/// or not (distinct from "checked and found nothing wrong" — conflating the two would silently
/// hide a real problem). Doesn't include a per-device "underpowered" case: no available macOS API
/// (system_profiler's `SPUSBHostDataType` JSON, `ioreg -p IOUSB`) exposes the "current required"
/// side of that comparison on this host stack — see SystemProfilerUSBPowerProvider for what was
/// tried and empirically ruled out.
public enum USBPowerCheckOutcome: Equatable {
    case ok
    case unavailable
}

public protocol USBPowerInspecting {
    /// Checks whether USB device enumeration is currently working.
    func checkPower() -> USBPowerCheckOutcome
}
