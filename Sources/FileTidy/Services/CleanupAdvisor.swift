import Foundation

/// Flags files that are usually safe to throw away once a download has run its course.
enum CleanupAdvisor {
    /// `.torrent` files are just download metadata; once the download is done they're clutter.
    static func isTorrent(_ file: ScannedFile) -> Bool {
        file.url.pathExtension.lowercased() == "torrent"
    }

    /// A `.zip` is considered "already extracted" when a file or folder with the same
    /// base name already sits next to it (the classic signature left by macOS's
    /// built-in Archive Utility / most unzip tools).
    static func isExtractedArchive(_ file: ScannedFile, allNames: Set<String>) -> Bool {
        guard file.url.pathExtension.lowercased() == "zip" else { return false }
        let baseName = file.url.deletingPathExtension().lastPathComponent
        return allNames.contains(baseName)
    }
}
