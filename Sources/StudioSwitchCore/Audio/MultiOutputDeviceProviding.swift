import CoreAudio

public enum MultiOutputDeviceError: Error, Equatable {
    case subDeviceNotFound(String)
    case missingUID(String)
    case creationFailed(OSStatus)
    /// A device already exists under `deviceName` but isn't composed of the expected sub-devices
    /// — e.g. something else (the user, another app) created an unrelated device under the same
    /// name. Refusing to reuse it beats silently routing audio through the wrong device.
    case nameCollision(String)
}

public protocol MultiOutputDeviceProviding {
    /// Ensures a device named `deviceName` combining `subDeviceNames` exists (creating a
    /// Multi-Output Device for it if needed) and returns its name, ready to be set as the
    /// default output device.
    @discardableResult
    func ensureMultiOutputDevice(named deviceName: String, subDeviceNames: [String]) throws -> String
}
