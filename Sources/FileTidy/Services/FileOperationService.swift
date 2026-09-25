import Foundation

/// Performs the actual filesystem changes. Deletions always go through the Trash
/// (`FileManager.trashItem`) so every action stays reversible from the Finder.
enum FileOperationService {
    static func moveFile(_ url: URL, toCategoryFolder folderName: String, in root: URL) throws {
        let fm = FileManager.default
        let destDir = root.appendingPathComponent(folderName, isDirectory: true)
        if !fm.fileExists(atPath: destDir.path) {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        }
        let destURL = uniqueURL(for: destDir.appendingPathComponent(url.lastPathComponent))
        try fm.moveItem(at: url, to: destURL)
    }

    static func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Appends " 2", " 3", ... before the extension if something already exists at `url`,
    /// so a move never silently overwrites an existing file.
    private static func uniqueURL(for url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }

        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()

        var counter = 2
        var candidate = url
        while fm.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }
}
