import Foundation

public final class FileManagerUADSessionLister: UADSessionListing {
    private let sessionsDirectory: String
    private let fileManager: FileManager

    public init(sessionsDirectory: String = "~/Documents/Universal Audio/Sessions", fileManager: FileManager = .default) {
        self.sessionsDirectory = sessionsDirectory
        self.fileManager = fileManager
    }

    public func listSessions() -> [UADSessionFile] {
        let expandedDirectory = (sessionsDirectory as NSString).expandingTildeInPath
        guard let contents = try? fileManager.contentsOfDirectory(atPath: expandedDirectory) else {
            return []
        }

        return contents
            .filter { $0.hasSuffix(".uadmix") }
            .map { fileName in
                UADSessionFile(
                    name: (fileName as NSString).deletingPathExtension,
                    path: (expandedDirectory as NSString).appendingPathComponent(fileName)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
