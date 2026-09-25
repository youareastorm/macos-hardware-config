import Foundation

/// What FileTidy proposes to do with a given file. The user decides whether
/// this actually happens via the checkbox on each row (`ScanItem.isSelected`).
enum ProposedAction {
    case move(to: FileCategory)
    case deleteTorrent
    case deleteExtractedArchive
}

/// A single file with a proposed action, and whether the user has it checked
/// to be applied. Reference type so SwiftUI toggles can bind to it directly.
final class ScanItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let size: Int64
    let modificationDate: Date
    let action: ProposedAction
    @Published var isSelected: Bool

    init(url: URL, size: Int64, modificationDate: Date, action: ProposedAction, isSelected: Bool) {
        self.url = url
        self.size = size
        self.modificationDate = modificationDate
        self.action = action
        self.isSelected = isSelected
    }

    var fileName: String { url.lastPathComponent }
}
