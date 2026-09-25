import Foundation

/// A category used to decide which subfolder a file should be moved into.
struct FileCategory: Identifiable, Hashable {
    let id: String
    let displayName: String
    let folderName: String
    let extensions: Set<String>

    static let images = FileCategory(
        id: "images", displayName: "Images", folderName: "Images",
        extensions: ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "svg", "webp", "raw", "cr2", "nef", "dng"]
    )
    static let documents = FileCategory(
        id: "documents", displayName: "Documents", folderName: "Documents",
        extensions: ["pdf", "doc", "docx", "pages", "txt", "rtf", "odt", "key", "ppt", "pptx", "numbers", "xls", "xlsx", "csv", "md"]
    )
    static let archives = FileCategory(
        id: "archives", displayName: "Archives", folderName: "Archives",
        extensions: ["zip", "rar", "7z", "tar", "gz", "bz2", "tgz", "xz"]
    )
    static let installers = FileCategory(
        id: "installers", displayName: "Installateurs", folderName: "Installateurs",
        extensions: ["dmg", "pkg", "iso"]
    )
    static let videos = FileCategory(
        id: "videos", displayName: "Vidéos", folderName: "Vidéos",
        extensions: ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv", "webm"]
    )
    static let audio = FileCategory(
        id: "audio", displayName: "Audio", folderName: "Audio",
        extensions: ["mp3", "wav", "aac", "flac", "m4a", "aiff", "ogg", "wma"]
    )
    /// Catch-all for anything that doesn't match a known category. Files in this
    /// category are still proposed for a move into an "Autres" folder.
    static let other = FileCategory(id: "other", displayName: "Autres", folderName: "Autres", extensions: [])

    static let allCategories: [FileCategory] = [.images, .documents, .archives, .installers, .videos, .audio]

    static func category(forExtension ext: String) -> FileCategory {
        let lower = ext.lowercased()
        return allCategories.first { $0.extensions.contains(lower) } ?? .other
    }
}
