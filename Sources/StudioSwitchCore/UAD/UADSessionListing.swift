public struct UADSessionFile: Equatable, Identifiable {
    public var id: String { path }
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public protocol UADSessionListing {
    /// UAD Console session files (`.uadmix`) found in the sessions folder, alphabetically by name.
    func listSessions() -> [UADSessionFile]
}
