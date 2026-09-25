import Foundation

/// One file within a group of byte-for-byte identical files.
final class DuplicateFileItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let size: Int64
    let modificationDate: Date
    /// Defaults to `true` for every copy except the one FileTidy suggests keeping.
    @Published var isSelectedForDeletion: Bool

    init(url: URL, size: Int64, modificationDate: Date, isSelectedForDeletion: Bool) {
        self.url = url
        self.size = size
        self.modificationDate = modificationDate
        self.isSelectedForDeletion = isSelectedForDeletion
    }

    var fileName: String { url.lastPathComponent }
}

/// A group of two or more files with identical content (same size + same SHA-256 hash).
final class DuplicateGroup: Identifiable, ObservableObject {
    let id = UUID()
    @Published var items: [DuplicateFileItem]

    init(items: [DuplicateFileItem]) {
        self.items = items
    }
}
