public protocol AudioDeviceStatusProviding {
    func isDeviceOnline(named deviceName: String) -> Bool
    func nominalSampleRate(forDeviceNamed deviceName: String) -> Double?
    func defaultOutputDeviceName() -> String?
    func defaultInputDeviceName() -> String?
    func builtInOutputDeviceName() -> String?
}
