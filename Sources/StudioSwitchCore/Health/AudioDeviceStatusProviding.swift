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

    /// All consecutive stereo channel pairs available on the device's output scope (e.g. 1/2, 3/4,
    /// 5/6), for presenting as choices — not just the one currently active. Empty when the device
    /// is offline or reports no output channels.
    func availableOutputChannelPairs(forDeviceNamed deviceName: String) -> [ChannelPair]
}
