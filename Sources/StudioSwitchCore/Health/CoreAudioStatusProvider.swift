import AudioToolbox
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

    public func outputChannelNames(forDeviceNamed deviceName: String) -> [String]? {
        guard let deviceID = deviceProvider.deviceID(named: deviceName) else { return nil }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var channels = [UInt32](repeating: 0, count: 2)
        var size = UInt32(MemoryLayout<UInt32>.size * 2)
        let status = channels.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer.baseAddress!)
        }
        guard status == noErr else { return nil }

        return channels.map { channelName(forDeviceID: deviceID, channel: $0) ?? "Canal \($0)" }
    }

    public func availableOutputChannelPairs(forDeviceNamed deviceName: String) -> [ChannelPair] {
        guard let deviceID = deviceProvider.deviceID(named: deviceName) else { return [] }
        let channelCount = outputChannelCount(for: deviceID)
        guard channelCount >= 2 else { return [] }

        var pairs: [ChannelPair] = []
        var channel: UInt32 = 1
        while channel + 1 <= channelCount {
            let firstName = channelName(forDeviceID: deviceID, channel: channel) ?? "Canal \(channel)"
            let secondName = channelName(forDeviceID: deviceID, channel: channel + 1) ?? "Canal \(channel + 1)"
            pairs.append(ChannelPair(firstChannel: channel, secondChannel: channel + 1, firstName: firstName, secondName: secondName))
            channel += 2
        }
        return pairs
    }

    private func outputChannelCount(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else { return 0 }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer) == noErr else { return 0 }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(into: UInt32(0)) { total, buffer in total += buffer.mNumberChannels }
    }

    private func channelName(forDeviceID deviceID: AudioDeviceID, channel: UInt32) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyElementName,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        let value = name as String
        return value.isEmpty ? nil : value
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
