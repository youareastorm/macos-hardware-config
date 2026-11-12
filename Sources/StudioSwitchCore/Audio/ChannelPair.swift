import CoreAudio

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

    /// The speaker layout that sends stereo to this pair, as Audio MIDI Setup's "Configure Speakers"
    /// writes it: one label per output channel, left and right on the pair, unknown everywhere else.
    /// The stereo pair alone isn't enough — on 2026-11-12 the pair was on VIRTUAL 1/2 but nothing
    /// was heard until the layout was fixed too.
    public func speakerLayoutLabels(channelCount: UInt32) -> [AudioChannelLabel] {
        (0..<channelCount).map { index in
            switch index + 1 {
            case firstChannel: return kAudioChannelLabel_Left
            case secondChannel: return kAudioChannelLabel_Right
            default: return kAudioChannelLabel_Unknown
            }
        }
    }
}
