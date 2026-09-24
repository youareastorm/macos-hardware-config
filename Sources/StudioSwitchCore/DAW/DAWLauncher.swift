import Foundation

public enum DAWLauncherError: Error, Equatable {
    case applicationNotFound(String)
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

    public func launch(_ daw: DAWEntry) throws {
        guard let appURL = appLocator.applicationURL(forBundleID: daw.bundleID) else {
            throw DAWLauncherError.applicationNotFound(daw.bundleID)
        }
        if let templatePath = daw.templatePath {
            let expandedPath = (templatePath as NSString).expandingTildeInPath
            if fileManager.fileExists(atPath: expandedPath) {
                try appLauncher.open(fileURL: URL(fileURLWithPath: expandedPath), withApplicationAt: appURL)
                return
            }
        }
        try appLauncher.launchApplication(at: appURL)
    }
}
