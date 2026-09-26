import CoreAudio

public enum MultiOutputDeviceError: Error, Equatable {
    case subDeviceNotFound(String)
    case missingUID(String)
    case creationFailed(OSStatus)
}

public protocol MultiOutputDeviceProviding {
    /// Ensures a device named `deviceName` combining `subDeviceNames` exists (creating a
    /// Multi-Output Device for it if needed) and returns its name, ready to be set as the
    /// default output device.
    @discardableResult
    func ensureMultiOutputDevice(named deviceName: String, subDeviceNames: [String]) throws -> String
}
