import Foundation

struct ScannedFile {
    let url: URL
    let size: Int64
    let modificationDate: Date
    let isDirectory: Bool
}

enum FolderScanner {
    /// Lists only the direct children of `folder` ("à sa racine") — never recurses
    /// into subfolders, so folders FileTidy already created (Images, Documents, ...)
    /// or any other subfolder are left untouched.
    static func scanRoot(_ folder: URL) throws -> [ScannedFile] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        let contents = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        return contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let isDir = values.isDirectory ?? false
            return ScannedFile(
                url: url,
                size: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate ?? Date.distantPast,
                isDirectory: isDir
            )
        }
    }
}
