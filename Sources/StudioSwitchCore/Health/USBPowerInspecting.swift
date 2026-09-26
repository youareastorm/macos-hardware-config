/// Outcome of a USB power check: whether every connected device is within its port's power
/// budget, which ones aren't, or whether the check couldn't be performed at all (distinct from
/// "checked and found nothing wrong" — conflating the two would silently hide a real problem).
public enum USBPowerCheckOutcome: Equatable {
    case ok
    case underpowered([String])
    case unavailable
}

public protocol USBPowerInspecting {
    /// Checks connected USB devices (hubs included) for ones currently drawing more current than
    /// their port can supply — the classic symptom of an unpowered/underpowered hub.
    func checkPower() -> USBPowerCheckOutcome
}
