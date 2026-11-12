import CoreAudio

/// A device's output speaker layout (`kAudioDevicePropertyPreferredChannelLayout`), the setting
/// behind Audio MIDI Setup's "Configure Speakers": one label per output channel.
enum SpeakerLayout {
    /// The 1-indexed channels labelled left and right, or `nil` when the layout can't be read or
    /// doesn't label both.
    static func leftAndRightChannels(of deviceID: AudioDeviceID) -> (left: UInt32, right: UInt32)? {
        var address = layoutAddress
        var size: UInt32 = 0
        guard AudioObjectHasProperty(deviceID, &address),
              AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioChannelLayout>.size) else { return nil }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioChannelLayout>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else { return nil }

        let layout = raw.assumingMemoryBound(to: AudioChannelLayout.self)
        let count = Int(layout.pointee.mNumberChannelDescriptions)
        let descriptions = UnsafeBufferPointer(start: raw.advanced(by: descriptionsOffset).assumingMemoryBound(to: AudioChannelDescription.self), count: count)
        var left: UInt32?
        var right: UInt32?
        for (index, description) in descriptions.enumerated() {
            if description.mChannelLabel == kAudioChannelLabel_Left { left = UInt32(index + 1) }
            if description.mChannelLabel == kAudioChannelLabel_Right { right = UInt32(index + 1) }
        }
        guard let left, let right else { return nil }
        return (left, right)
    }

    /// Writes one label per output channel, the way Audio MIDI Setup does (channel descriptions).
    static func write(_ labels: [AudioChannelLabel], to deviceID: AudioDeviceID) -> OSStatus {
        var address = layoutAddress
        let size = descriptionsOffset + labels.count * MemoryLayout<AudioChannelDescription>.stride
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioChannelLayout>.alignment)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)

        let layout = raw.assumingMemoryBound(to: AudioChannelLayout.self)
        layout.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
        layout.pointee.mChannelBitmap = []
        layout.pointee.mNumberChannelDescriptions = UInt32(labels.count)
        let descriptions = raw.advanced(by: descriptionsOffset).assumingMemoryBound(to: AudioChannelDescription.self)
        for (index, label) in labels.enumerated() {
            descriptions[index] = AudioChannelDescription(mChannelLabel: label, mChannelFlags: [], mCoordinates: (0, 0, 0))
        }
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(size), raw)
    }

    /// Number of output channels across the device's output streams.
    static func outputChannelCount(of deviceID: AudioDeviceID) -> UInt32 {
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

    private static let descriptionsOffset = MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions)!

    private static var layoutAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelLayout,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
