public protocol MIDIDeviceProviding {
    func iacDriverIsPresent() -> Bool
    func enableIACDriver() throws
}
