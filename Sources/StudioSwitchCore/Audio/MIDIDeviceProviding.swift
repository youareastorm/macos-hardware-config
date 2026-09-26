public protocol MIDIDeviceProviding {
    func iacDriverIsPresent() -> Bool
    func enableIACDriver() throws

    /// Brings any MIDI device online by its display name (`kMIDIPropertyName`), not just the IAC
    /// Driver — e.g. re-enabling a device the user just disabled in Audio MIDI Setup.
    func enableDevice(named deviceName: String) throws
}
