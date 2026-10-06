import CoreAudio
import Foundation

public protocol AudioDeviceListWatching {
    /// Calls `onChange` (from an arbitrary queue, possibly several times in a burst) every time
    /// the set of CoreAudio devices changes — an interface being plugged in, powered on, or
    /// removed. Fires for aggregate devices this app creates itself too, so callers must not
    /// assume a call means the physical hardware changed.
    func start(onChange: @escaping () -> Void)
}

public final class CoreAudioDeviceListWatcher: AudioDeviceListWatching {
    private let queue = DispatchQueue(label: "com.simonrenard.studioswitch.devicelist")
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var listener: AudioObjectPropertyListenerBlock?

    public init() {}

    public func start(onChange: @escaping () -> Void) {
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        listener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
    }

    deinit {
        if let listener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
        }
    }
}
