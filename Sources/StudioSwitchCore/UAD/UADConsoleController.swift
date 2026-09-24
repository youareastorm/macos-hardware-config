import Foundation

public protocol UADSessionOpening {
    func openSession(atPath path: String) throws
}

public enum UADConsoleControllerError: Error, Equatable {
    case sessionFileNotFound(String)
    case consoleAppNotFound(String)
}

public final class UADConsoleController: UADSessionOpening {
    public static let defaultConsoleAppPath = "/Applications/Universal Audio/UAD Console.app"

    private let appLauncher: AppLaunching
    private let fileManager: FileManager
    private let consoleAppPath: String

    public init(appLauncher: AppLaunching = WorkspaceAppLauncher(), fileManager: FileManager = .default, consoleAppPath: String = UADConsoleController.defaultConsoleAppPath) {
        self.appLauncher = appLauncher
        self.fileManager = fileManager
        self.consoleAppPath = consoleAppPath
    }

    public func openSession(atPath path: String) throws {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: expandedPath) else {
            throw UADConsoleControllerError.sessionFileNotFound(expandedPath)
        }
        guard fileManager.fileExists(atPath: consoleAppPath) else {
            throw UADConsoleControllerError.consoleAppNotFound(consoleAppPath)
        }
        try appLauncher.open(fileURL: URL(fileURLWithPath: expandedPath), withApplicationAt: URL(fileURLWithPath: consoleAppPath))
    }
}
