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
    public static let defaultConsoleBundleID = "com.uaudio.console3"

    private let appLauncher: AppLaunching
    private let fileManager: FileManager
    private let consoleAppPath: String
    private let consoleBundleID: String
    private let runningChecker: RunningApplicationChecking
    private let sessionLoader: UADConsoleSessionLoading

    public init(
        appLauncher: AppLaunching = WorkspaceAppLauncher(),
        fileManager: FileManager = .default,
        consoleAppPath: String = UADConsoleController.defaultConsoleAppPath,
        consoleBundleID: String = UADConsoleController.defaultConsoleBundleID,
        runningChecker: RunningApplicationChecking = WorkspaceRunningApplicationChecker(),
        sessionLoader: UADConsoleSessionLoading = AppleScriptUADConsoleSessionLoader()
    ) {
        self.appLauncher = appLauncher
        self.fileManager = fileManager
        self.consoleAppPath = consoleAppPath
        self.consoleBundleID = consoleBundleID
        self.runningChecker = runningChecker
        self.sessionLoader = sessionLoader
    }

    public func openSession(atPath path: String) throws {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: expandedPath) else {
            throw UADConsoleControllerError.sessionFileNotFound(expandedPath)
        }
        guard fileManager.fileExists(atPath: consoleAppPath) else {
            throw UADConsoleControllerError.consoleAppNotFound(consoleAppPath)
        }

        if runningChecker.isRunning(bundleID: consoleBundleID) {
            // UAD Console is already open with some session — a plain file-open is silently
            // ignored (see AppleScriptUADConsoleSessionLoader), so drive its File > Open... menu.
            try sessionLoader.loadSession(atPath: expandedPath)
        } else {
            try appLauncher.open(fileURL: URL(fileURLWithPath: expandedPath), withApplicationAt: URL(fileURLWithPath: consoleAppPath))
        }
    }
}
