import Foundation

/// A top-level folder the user has chosen to have FileTidy analyze and tidy up.
/// Only the direct contents of this folder (its "root") are ever scanned.
struct WatchedFolder: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case desktop, downloads, custom
    }

    let id: UUID
    var kind: Kind
    var path: String
    var displayName: String

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    static func builtIn() -> [WatchedFolder] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            WatchedFolder(
                id: UUID(), kind: .desktop,
                path: home.appendingPathComponent("Desktop").path,
                displayName: "Bureau"
            ),
            WatchedFolder(
                id: UUID(), kind: .downloads,
                path: home.appendingPathComponent("Downloads").path,
                displayName: "Téléchargements"
            ),
        ]
    }
}
