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
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    public func open(fileURL: URL, withApplicationAt appURL: URL) throws {
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
