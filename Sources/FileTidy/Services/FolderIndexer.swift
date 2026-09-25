import Foundation

/// A folder FileTidy could reuse as a destination: either sitting directly at the
/// watched root, or one level inside a category folder (e.g. "Documents/Factures").
struct ExistingFolder {
    let name: String
    let relativePath: String
}

enum FolderIndexer {
    /// Builds the list of folders FileTidy can propose as a destination, from what's
    /// already there. This never recurses more than one level deep and never reads
    /// file contents, so it stays cheap even on a large, deeply-nested Documents folder.
    static func index(rootContents: [ScannedFile]) -> [ExistingFolder] {
        let fm = FileManager.default
        var result: [ExistingFolder] = []

        for entry in rootContents where entry.isDirectory {
            let name = entry.url.lastPathComponent
            result.append(ExistingFolder(name: name, relativePath: name))

            guard let children = try? fm.contentsOfDirectory(
                at: entry.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                guard let isDir = try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir else { continue }
                result.append(ExistingFolder(name: child.lastPathComponent, relativePath: name + "/" + child.lastPathComponent))
            }
        }
        return result
    }
}
