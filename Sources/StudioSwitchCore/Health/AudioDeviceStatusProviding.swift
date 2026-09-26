public protocol AudioDeviceStatusProviding {
    func isDeviceOnline(named deviceName: String) -> Bool
    func nominalSampleRate(forDeviceNamed deviceName: String) -> Double?
    func defaultOutputDeviceName() -> String?
    func defaultInputDeviceName() -> String?
    func builtInOutputDeviceName() -> String?

    /// Names of the two channels currently mapped as the device's default stereo output pair
    /// (left, right) — e.g. `["VIRTUAL 1", "VIRTUAL 2"]` on a UA Apollo configured to route to its
    /// software-return channels via Audio MIDI Setup's "Configurer la disposition" dialog. `nil`
    /// when the device is offline or has no stereo pair configured.
    func outputChannelNames(forDeviceNamed deviceName: String) -> [String]?
}
