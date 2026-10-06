import Foundation

public protocol UADSessionOpening {
    func openSession(atPath path: String) throws
}

public protocol UADConsoleSessionEnsuring {
    /// Makes sure UAD Console is running with the given session open: launches it with that
    /// session when it isn't running, loads the session when a different one is open, and does
    /// nothing when it's already the open one.
    func ensureSessionOpen(atPath path: String) throws
}

public enum UADConsoleControllerError: Error, Equatable {
    case sessionFileNotFound(String)
    case consoleAppNotFound(String)
}

public final class UADConsoleController: UADSessionOpening, UADConsoleSessionEnsuring {
    public static let defaultConsoleAppPath = "/Applications/Universal Audio/UAD Console.app"
    public static let defaultConsoleBundleID = "com.uaudio.console3"

    private let appLauncher: AppLaunching
    private let fileManager: FileManager
    private let consoleAppPath: String
    private let consoleBundleID: String
    private let runningChecker: RunningApplicationChecking
    private let sessionLoader: UADConsoleSessionLoading
    private let sessionInspector: UADConsoleSessionInspecting

    public init(
        appLauncher: AppLaunching = WorkspaceAppLauncher(),
        fileManager: FileManager = .default,
        consoleAppPath: String = UADConsoleController.defaultConsoleAppPath,
        consoleBundleID: String = UADConsoleController.defaultConsoleBundleID,
        runningChecker: RunningApplicationChecking = WorkspaceRunningApplicationChecker(),
        sessionLoader: UADConsoleSessionLoading = AppleScriptUADConsoleSessionLoader(),
        sessionInspector: UADConsoleSessionInspecting = AppleScriptUADConsoleSessionInspector()
    ) {
        self.appLauncher = appLauncher
        self.fileManager = fileManager
        self.consoleAppPath = consoleAppPath
        self.consoleBundleID = consoleBundleID
        self.runningChecker = runningChecker
        self.sessionLoader = sessionLoader
        self.sessionInspector = sessionInspector
    }

    public func ensureSessionOpen(atPath path: String) throws {
        if runningChecker.isRunning(bundleID: consoleBundleID),
           let openTitle = sessionInspector.currentSessionName(),
           Self.sessionName(fromWindowTitle: openTitle).caseInsensitiveCompare(Self.sessionName(fromPath: path)) == .orderedSame {
            return
        }
        try openSession(atPath: path)
    }

    /// "UAD Console: OCTO EMPTY*" → "OCTO EMPTY" (the trailing asterisk marks unsaved changes).
    static func sessionName(fromWindowTitle title: String) -> String {
        var name = title.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("UAD Console:") { name = String(name.dropFirst("UAD Console:".count)) }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.hasSuffix("*") { name = String(name.dropLast()).trimmingCharacters(in: .whitespaces) }
        return name
    }

    static func sessionName(fromPath path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
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
