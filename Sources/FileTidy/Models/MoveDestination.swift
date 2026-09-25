import Foundation

/// Why FileTidy picked this destination for a file — shown to the user so a
/// proposal never feels arbitrary.
enum DestinationKind {
    /// The file's name shares a meaningful word with a folder that already exists
    /// (at the watched root, or one level inside a category folder).
    case existingFolder
    /// The file's name shares a stem with at least one other loose file, so
    /// FileTidy proposes creating a brand-new, more specific folder for the group.
    case newFolder
    /// No smart match found: falls back to the plain type-based category folder.
    case defaultCategory
}

/// Where a file should go, relative to the watched folder's root (e.g. "Documents/Factures").
struct MoveDestination {
    let relativePath: String
    let displayName: String
    let category: FileCategory
    let kind: DestinationKind
}
