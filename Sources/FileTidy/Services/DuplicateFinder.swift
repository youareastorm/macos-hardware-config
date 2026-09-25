import Foundation
import CryptoKit

enum DuplicateFinder {
    /// Groups files that are byte-for-byte identical. Files are first grouped by size
    /// (cheap) and only hashed when at least one other file shares that size, so
    /// scanning a folder full of unique files stays fast.
    static func findDuplicates(among files: [ScannedFile]) -> [[ScannedFile]] {
        let bySize = Dictionary(grouping: files, by: { $0.size })
        var groups: [[ScannedFile]] = []

        for (size, candidates) in bySize where size > 0 && candidates.count > 1 {
            var byHash: [String: [ScannedFile]] = [:]
            for file in candidates {
                guard let digest = sha256(of: file.url) else { continue }
                byHash[digest, default: []].append(file)
            }
            for (_, sameHash) in byHash where sameHash.count > 1 {
                groups.append(sameHash)
            }
        }
        return groups
    }

    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1_048_576) // 1 MB at a time
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
