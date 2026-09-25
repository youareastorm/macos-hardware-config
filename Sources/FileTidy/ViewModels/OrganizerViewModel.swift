import Foundation
import SwiftUI

@MainActor
final class OrganizerViewModel: ObservableObject {
    @Published var watchedFolders: [WatchedFolder]
    @Published var selectedFolderID: WatchedFolder.ID?

    @Published var moveItems: [ScanItem] = []
    @Published var cleanupItems: [ScanItem] = []
    @Published var duplicateGroups: [DuplicateGroup] = []

    @Published var isScanning = false
    @Published var lastError: String?
    @Published var lastSummary: String?

    private let customFoldersKey = "com.filetidy.customFolders"

    init() {
        var folders = WatchedFolder.builtIn()
        if let data = UserDefaults.standard.data(forKey: customFoldersKey),
           let saved = try? JSONDecoder().decode([WatchedFolder].self, from: data) {
            folders.append(contentsOf: saved)
        }
        self.watchedFolders = folders
        self.selectedFolderID = folders.first?.id
    }

    var selectedFolder: WatchedFolder? {
        watchedFolders.first { $0.id == selectedFolderID }
    }

    func addCustomFolder(url: URL) {
        guard !watchedFolders.contains(where: { $0.path == url.path }) else { return }
        let folder = WatchedFolder(id: UUID(), kind: .custom, path: url.path, displayName: url.lastPathComponent)
        watchedFolders.append(folder)
        persistCustomFolders()
        selectedFolderID = folder.id
    }

    func removeCustomFolder(_ folder: WatchedFolder) {
        guard folder.kind == .custom else { return }
        watchedFolders.removeAll { $0.id == folder.id }
        persistCustomFolders()
        if selectedFolderID == folder.id {
            selectedFolderID = watchedFolders.first?.id
        }
    }

    private func persistCustomFolders() {
        let custom = watchedFolders.filter { $0.kind == .custom }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: customFoldersKey)
        }
    }

    func scanSelectedFolder() {
        guard let folder = selectedFolder else { return }
        isScanning = true
        lastError = nil
        moveItems = []
        cleanupItems = []
        duplicateGroups = []

        let folderURL = folder.url

        Task.detached { [weak self] in
            do {
                let scanned = try FolderScanner.scanRoot(folderURL)
                let allNames = Set(scanned.map { $0.url.lastPathComponent })
                let files = scanned.filter { !$0.isDirectory }

                var moves: [ScanItem] = []
                var cleanups: [ScanItem] = []

                for file in files {
                    if CleanupAdvisor.isTorrent(file) {
                        cleanups.append(ScanItem(
                            url: file.url, size: file.size, modificationDate: file.modificationDate,
                            action: .deleteTorrent, isSelected: false
                        ))
                        continue
                    }
                    if CleanupAdvisor.isExtractedArchive(file, allNames: allNames) {
                        cleanups.append(ScanItem(
                            url: file.url, size: file.size, modificationDate: file.modificationDate,
                            action: .deleteExtractedArchive, isSelected: false
                        ))
                        continue
                    }
                    let category = FileCategory.category(forExtension: file.url.pathExtension)
                    moves.append(ScanItem(
                        url: file.url, size: file.size, modificationDate: file.modificationDate,
                        action: .move(to: category), isSelected: true
                    ))
                }

                let rawDuplicates = DuplicateFinder.findDuplicates(among: files)
                let duplicates: [DuplicateGroup] = rawDuplicates.map { group in
                    let sorted = group.sorted { $0.modificationDate < $1.modificationDate }
                    let items = sorted.enumerated().map { index, f in
                        // Keep the oldest copy by default; flag the rest for deletion.
                        DuplicateFileItem(url: f.url, size: f.size, modificationDate: f.modificationDate, isSelectedForDeletion: index != 0)
                    }
                    return DuplicateGroup(items: items)
                }

                // Files flagged for deletion as duplicates shouldn't also appear as
                // "to move" proposals; the copy being kept still gets organized normally.
                let urlsHandledAsDuplicates = Set(
                    duplicates.flatMap { $0.items.filter(\.isSelectedForDeletion).map(\.url) }
                )
                moves.removeAll { urlsHandledAsDuplicates.contains($0.url) }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.moveItems = moves
                    self.cleanupItems = cleanups
                    self.duplicateGroups = duplicates
                    self.isScanning = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.lastError = error.localizedDescription
                    self.isScanning = false
                }
            }
        }
    }

    func applySelected() {
        guard let folder = selectedFolder else { return }
        var moved = 0
        var deleted = 0
        var failed = 0

        for item in moveItems where item.isSelected {
            if case .move(let category) = item.action {
                do {
                    try FileOperationService.moveFile(item.url, toCategoryFolder: category.folderName, in: folder.url)
                    moved += 1
                } catch {
                    failed += 1
                }
            }
        }

        for item in cleanupItems where item.isSelected {
            do {
                try FileOperationService.trash(item.url)
                deleted += 1
            } catch {
                failed += 1
            }
        }

        for group in duplicateGroups {
            for duplicate in group.items where duplicate.isSelectedForDeletion {
                do {
                    try FileOperationService.trash(duplicate.url)
                    deleted += 1
                } catch {
                    failed += 1
                }
            }
        }

        var summary = "\(moved) fichier(s) rangé(s), \(deleted) fichier(s) mis à la corbeille"
        if failed > 0 { summary += ", \(failed) échec(s)" }
        lastSummary = summary

        scanSelectedFolder()
    }
}
