import AppKit
import Foundation

public protocol AppLocating {
    func applicationURL(forBundleID bundleID: String) -> URL?
}

public protocol AppLaunching {
    func launchApplication(at appURL: URL) throws
    func open(fileURL: URL, withApplicationAt appURL: URL) throws
}

public final class WorkspaceAppLocator: AppLocating {
    public init() {}

    public func applicationURL(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

public final class WorkspaceAppLauncher: AppLaunching {
    public init() {}

    public func launchApplication(at appURL: URL) throws {
        try Self.awaitCompletion { completion in
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: completion)
        }
    }

    public func open(fileURL: URL, withApplicationAt appURL: URL) throws {
        try Self.awaitCompletion { completion in
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: completion)
        }
    }

    private static func awaitCompletion(_ operation: (@escaping (NSRunningApplication?, Error?) -> Void) -> Void) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var launchError: Error?
        operation { _, error in
            launchError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let launchError { throw launchError }
    }
}
