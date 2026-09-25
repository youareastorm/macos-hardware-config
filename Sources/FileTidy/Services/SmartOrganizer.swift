import Foundation

/// Decides, per file, whether to reuse an existing folder that matches its name,
/// group it with similarly-named files into a brand-new folder, or fall back to
/// the plain type-based category. Pure string/set operations on file names only
/// (no file content is read), so this stays essentially free CPU-wise even on a
/// folder with hundreds of items.
enum SmartOrganizer {
    private static let stopWords: Set<String> = [
        "copy", "copie", "final", "finale", "definitif", "definitive", "version",
        "nouveau", "nouvelle", "ancien", "ancienne", "draft", "brouillon",
        "untitled", "sans", "titre", "the", "and", "les", "des", "une",
    ]

    /// Builds the destination for every loose file in one pass: existing-folder
    /// name matches first, then stem-based grouping for what's left, then the
    /// plain category as a last resort.
    static func plan(for files: [ScannedFile], existingFolders: [ExistingFolder]) -> [URL: MoveDestination] {
        let genericCategoryNames = Set(FileCategory.allCategories.map { $0.folderName.lowercased() })
        // A bare top-level folder that just IS a generic category (e.g. a plain
        // "Images" folder) isn't a "smart" match — it's what the default fallback
        // already produces. Only folders more specific than that count as smart.
        let smartCandidates = existingFolders.filter { folder in
            !(!folder.relativePath.contains("/") && genericCategoryNames.contains(folder.name.lowercased()))
        }

        var result: [URL: MoveDestination] = [:]
        var remaining: [ScannedFile] = []

        for file in files {
            let category = FileCategory.category(forExtension: file.url.pathExtension)
            if let match = matchExistingFolder(fileName: file.url.lastPathComponent, in: smartCandidates) {
                result[file.url] = MoveDestination(
                    relativePath: match.relativePath, displayName: match.name, category: category, kind: .existingFolder
                )
            } else {
                remaining.append(file)
            }
        }

        let byCategory = Dictionary(grouping: remaining) { FileCategory.category(forExtension: $0.url.pathExtension) }
        for (category, categoryFiles) in byCategory {
            var claimed = Set<URL>()
            for (stem, group) in groupByStem(categoryFiles) {
                let folderName = titleCase(stem)
                let relativePath = category.folderName + "/" + folderName
                for file in group {
                    result[file.url] = MoveDestination(
                        relativePath: relativePath, displayName: folderName, category: category, kind: .newFolder
                    )
                    claimed.insert(file.url)
                }
            }
            for file in categoryFiles where !claimed.contains(file.url) {
                result[file.url] = MoveDestination(
                    relativePath: category.folderName, displayName: category.folderName, category: category, kind: .defaultCategory
                )
            }
        }
        return result
    }

    // MARK: - Existing-folder matching

    private static func matchExistingFolder(fileName: String, in folders: [ExistingFolder]) -> ExistingFolder? {
        let fileTokens = tokens(from: (fileName as NSString).deletingPathExtension)
        guard !fileTokens.isEmpty else { return nil }

        var best: (folder: ExistingFolder, score: Int)?
        for folder in folders {
            let score = fileTokens.intersection(tokens(from: folder.name)).count
            guard score > 0 else { continue }
            if best == nil || score > best!.score {
                best = (folder, score)
            }
        }
        return best?.folder
    }

    private static func tokens(from name: String) -> Set<String> {
        let lower = name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let separators = CharacterSet(charactersIn: "-_ .()[]")
        return Set(
            lower.components(separatedBy: separators).compactMap { token -> String? in
                var t = token
                if t.count > 3, t.hasSuffix("s") { t.removeLast() }
                guard t.count >= 4, !stopWords.contains(t) else { return nil }
                guard t.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil else { return nil }
                return t
            }
        )
    }

    // MARK: - Stem grouping (proposes a brand-new folder)

    /// Groups files whose name — once a trailing counter/version-like word is
    /// stripped — is identical, e.g. "rapport-final-v1.pdf" and "rapport-final-v2.pdf"
    /// both reduce to the stem "rapport final".
    private static func groupByStem(_ files: [ScannedFile]) -> [String: [ScannedFile]] {
        var groups: [String: [ScannedFile]] = [:]
        for file in files {
            guard let stem = meaningfulStem(of: file.url.deletingPathExtension().lastPathComponent) else { continue }
            groups[stem, default: []].append(file)
        }
        return groups.filter { $0.value.count >= 2 }
    }

    private static func meaningfulStem(of baseName: String) -> String? {
        let lower = baseName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        var parts = lower.components(separatedBy: CharacterSet(charactersIn: "-_ ")).filter { !$0.isEmpty }

        while let last = parts.last, isCounterToken(last) {
            parts.removeLast()
        }
        guard !parts.isEmpty else { return nil }

        let stem = parts.joined(separator: " ")
        guard stem.count >= 4 else { return nil }
        return stem
    }

    private static func isCounterToken(_ token: String) -> Bool {
        if token.allSatisfy(\.isNumber) { return true }
        if stopWords.contains(token) { return true }
        // "v1", "v2", "n3"...
        if token.count <= 2, let first = token.first, first.isLetter, token.dropFirst().allSatisfy(\.isNumber) { return true }
        // "(1)", "(2)"...
        if token.hasPrefix("("), token.hasSuffix(")"), token.dropFirst().dropLast().allSatisfy(\.isNumber) { return true }
        return false
    }

    private static func titleCase(_ stem: String) -> String {
        stem.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
