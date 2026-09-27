import CoreAudio
import Foundation

/// Creates and reuses macOS Multi-Output Devices via CoreAudio's aggregate device API, so a
/// profile can route its output to several devices at once (e.g. two virtual outputs) without
/// requiring the user to have pre-built one in Audio MIDI Setup.
public final class CoreAudioMultiOutputDeviceProvider: MultiOutputDeviceProviding {
    private let deviceProvider: AudioDeviceProviding
    private let retryDelay: (TimeInterval) -> Void

    /// After a real `AudioHardwareCreateAggregateDevice` success, the new device isn't always
    /// immediately visible through `kAudioHardwarePropertyDevices` — verified on real hardware:
    /// calling `ensureMultiOutputDevice` again right after creating a device (same process, no
    /// deliberate wait) found the device NOT yet enumerable, attempted to create it again, and
    /// got back `kAudioHardwareIllegalOperationError` ('nope') because the UID was already taken.
    /// A later call (a few seconds on, even from a fresh process) found it fine. These bound how
    /// long the recovery below waits for the HAL to catch up before giving up.
    private static let creationRetryCount = 5
    private static let creationRetryDelay: TimeInterval = 0.3

    public init(
        deviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider(),
        retryDelay: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.deviceProvider = deviceProvider
        self.retryDelay = retryDelay
    }

    @discardableResult
    public func ensureMultiOutputDevice(named deviceName: String, subDeviceNames: [String]) throws -> String {
        if let existingDeviceID = deviceProvider.deviceID(named: deviceName) {
            try verifyComposition(of: existingDeviceID, named: deviceName, expectedSubDeviceNames: subDeviceNames)
            return deviceName
        }

        let subDeviceUIDs = try subDeviceNames.map { name -> String in
            guard let deviceID = deviceProvider.deviceID(named: name) else {
                throw MultiOutputDeviceError.subDeviceNotFound(name)
            }
            guard let uid = deviceUID(for: deviceID) else {
                throw MultiOutputDeviceError.missingUID(name)
            }
            return uid
        }
        guard !subDeviceUIDs.isEmpty else {
            throw MultiOutputDeviceError.subDeviceNotFound(deviceName)
        }

        let description = Self.aggregateDeviceDescription(name: deviceName, subDeviceUIDs: subDeviceUIDs)

        var aggregateDeviceID: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
        if status == noErr {
            return deviceName
        }
        guard status == kAudioHardwareIllegalOperationError else {
            throw MultiOutputDeviceError.creationFailed(status)
        }

        return try waitForNewlyVisibleDevice(named: deviceName, expectedSubDeviceNames: subDeviceNames, fallbackStatus: status)
    }

    /// Polls `deviceProvider` for a device this same call just tried (and failed) to create,
    /// because the HAL rejected it as a duplicate of one that was created moments ago but hasn't
    /// propagated into the device list yet. Surfaces the original creation error if the device
    /// still never shows up, rather than pretending the retry always finds one.
    func waitForNewlyVisibleDevice(named deviceName: String, expectedSubDeviceNames: [String], fallbackStatus: OSStatus) throws -> String {
        for attempt in 0..<Self.creationRetryCount {
            if attempt > 0 { retryDelay(Self.creationRetryDelay) }
            if let deviceID = deviceProvider.deviceID(named: deviceName) {
                try verifyComposition(of: deviceID, named: deviceName, expectedSubDeviceNames: expectedSubDeviceNames)
                return deviceName
            }
        }
        throw MultiOutputDeviceError.creationFailed(fallbackStatus)
    }

    /// Guards the fast path (device already exists → reuse it) against a name collision with
    /// something unrelated, without weakening it otherwise: this only ever *adds* a failure, and
    /// only when there's positive proof of a mismatch — both the existing device's real
    /// composition and every expected sub-device's UID must resolve, and disagree. If a sub-device
    /// is momentarily not enumerated (a virtual driver still starting up, say), that's not evidence
    /// of a problem, so this silently allows reuse exactly as it did before this check existed —
    /// turning a transient hiccup into a hard failure here would be a worse trade than the rare
    /// collision this check catches.
    private func verifyComposition(of deviceID: AudioDeviceID, named deviceName: String, expectedSubDeviceNames: [String]) throws {
        guard let actualUIDs = currentSubDeviceUIDs(of: deviceID) else { return }

        let expectedUIDs = expectedSubDeviceNames.compactMap { name in
            deviceProvider.deviceID(named: name).flatMap(deviceUID(for:))
        }
        guard expectedUIDs.count == expectedSubDeviceNames.count else { return }

        guard Set(actualUIDs) == Set(expectedUIDs) else {
            throw MultiOutputDeviceError.nameCollision(deviceName)
        }
    }

    /// The `AudioHardwareCreateAggregateDevice` description dictionary, pulled out as a pure
    /// function so its exact shape (which keys, the "stacked"/Multi-Output flag, drift
    /// compensation on every sub-device, the first sub-device as clock master) can be unit tested
    /// without a real device — the highest-risk part of this class, since a wrong key here fails
    /// silently at runtime rather than at compile time.
    static func aggregateDeviceDescription(name: String, subDeviceUIDs: [String]) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: "com.simonrenard.studioswitch.multioutput.\(name)",
            kAudioAggregateDeviceMainSubDeviceKey: subDeviceUIDs[0],
            kAudioAggregateDeviceIsPrivateKey: false,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceSubDeviceListKey: subDeviceUIDs.map { uid in
                [kAudioSubDeviceUIDKey: uid, kAudioSubDeviceDriftCompensationKey: true]
            }
        ]
    }

    private func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? (uid as String) : nil
    }

    /// UIDs of every sub-device actually making up an existing aggregate device, so a name match
    /// can be verified rather than trusted blindly. `kAudioAggregateDevicePropertyFullSubDeviceList`
    /// is the read-back counterpart of the `kAudioAggregateDeviceSubDeviceListKey` used at creation.
    private func currentSubDeviceUIDs(of deviceID: AudioDeviceID) -> [String]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyFullSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else { return nil }

        var array: CFArray = [] as CFArray
        let status = withUnsafeMutablePointer(to: &array) { pointer -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr, let uids = array as? [String] else { return nil }
        return uids
    }
}
