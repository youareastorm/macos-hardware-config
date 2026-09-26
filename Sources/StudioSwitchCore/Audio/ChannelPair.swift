/// A stereo pair of output channels on an audio device, by channel number (1-indexed, as CoreAudio
/// numbers them) and their user-facing names (e.g. "Virtual 1", "Virtual 2").
public struct ChannelPair: Equatable {
    public let firstChannel: UInt32
    public let secondChannel: UInt32
    public let firstName: String
    public let secondName: String

    public init(firstChannel: UInt32, secondChannel: UInt32, firstName: String, secondName: String) {
        self.firstChannel = firstChannel
        self.secondChannel = secondChannel
        self.firstName = firstName
        self.secondName = secondName
    }

    public var displayName: String { "\(firstName) / \(secondName)" }
}
