import Foundation

public enum DAWLauncherError: Error, Equatable {
    case applicationNotFound(String)
}

public enum DAWLaunchOutcome: Equatable {
    case launched
    case launchedWithoutTemplate(String)
}

public final class DAWLauncher {
    private let appLocator: AppLocating
    private let appLauncher: AppLaunching
    private let fileManager: FileManager

    public init(appLocator: AppLocating = WorkspaceAppLocator(), appLauncher: AppLaunching = WorkspaceAppLauncher(), fileManager: FileManager = .default) {
        self.appLocator = appLocator
        self.appLauncher = appLauncher
        self.fileManager = fileManager
    }

    public func launch(_ daw: DAWEntry) throws -> DAWLaunchOutcome {
        let appURL = try resolveAppURL(for: daw)

        if let templatePath = daw.templatePath {
            let expandedPath = (templatePath as NSString).expandingTildeInPath
            if fileManager.fileExists(atPath: expandedPath) {
                try appLauncher.open(fileURL: URL(fileURLWithPath: expandedPath), withApplicationAt: appURL)
                return .launched
            }
            try appLauncher.launchApplication(at: appURL)
            return .launchedWithoutTemplate(expandedPath)
        }

        try appLauncher.launchApplication(at: appURL)
        return .launched
    }

    private func resolveAppURL(for daw: DAWEntry) throws -> URL {
        if let appPath = daw.appPath {
            return URL(fileURLWithPath: (appPath as NSString).expandingTildeInPath)
        }
        guard let appURL = appLocator.applicationURL(forBundleID: daw.bundleID) else {
            throw DAWLauncherError.applicationNotFound(daw.bundleID)
        }
        return appURL
    }
}
