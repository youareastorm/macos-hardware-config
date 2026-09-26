import CoreAudio

public final class CoreAudioStatusProvider: AudioDeviceStatusProviding {
    private let deviceProvider: AudioDeviceProviding

    public init(deviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider()) {
        self.deviceProvider = deviceProvider
    }

    public func isDeviceOnline(named deviceName: String) -> Bool {
        deviceProvider.deviceID(named: deviceName) != nil
    }

    public func nominalSampleRate(forDeviceNamed deviceName: String) -> Double? {
        guard let deviceID = deviceProvider.deviceID(named: deviceName) else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        return status == noErr ? sampleRate : nil
    }

    public func defaultOutputDeviceName() -> String? {
        defaultDeviceName(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    public func defaultInputDeviceName() -> String? {
        defaultDeviceName(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    public func builtInOutputDeviceName() -> String? {
        for name in deviceProvider.connectedDeviceNames() {
            guard let deviceID = deviceProvider.deviceID(named: name),
                  let transportType = transportType(for: deviceID),
                  transportType == kAudioDeviceTransportTypeBuiltIn else { continue }
            return name
        }
        return nil
    }

    private func defaultDeviceName(selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr else { return nil }
        return deviceProvider.connectedDeviceNames().first { deviceProvider.deviceID(named: $0) == deviceID }
    }

    private func transportType(for deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transportType)
        return status == noErr ? transportType : nil
    }
}
