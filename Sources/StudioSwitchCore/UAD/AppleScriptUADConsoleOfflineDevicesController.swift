import Foundation

public enum UADConsoleOfflineDevicesError: Error, Equatable {
    case scriptFailed(String)
    case preferenceUnreadable
    case stillShowing
}

public protocol UADConsoleOfflineDevicesControlling {
    func isShowingOfflineDevices() throws -> Bool
    /// Unchecks View > Offline Devices if it's checked, then confirms it's unchecked.
    func hideOfflineDevices() throws
}

/// UAD Console's View > Offline Devices item (checked = show units that aren't connected, e.g. the
/// studio's Apollo x8 at home, appended after the connected unit's channels). It's a Console UI
/// preference, not something the UA Mixer Engine exposes.
///
/// The state is read from `"Show Offline Devices"` in `~/Library/Preferences/Universal Audio/UAD
/// ConsolePrefs.json`, which Console rewrites as soon as the item is clicked (seen on real hardware
/// with UAD Console 1.3.1, both ways). Reading the menu itself isn't usable: its check mark only
/// refreshes when the menu is opened, which would bring Console forward on every health check.
/// Unchecking still goes through the menu with System Events (same Accessibility grant as the
/// session switch) and needs UAD Console to be running.
public final class AppleScriptUADConsoleOfflineDevicesController: UADConsoleOfflineDevicesControlling {
    private static let clickScript = """
    tell application "System Events" to tell process "UAD Console"
        click menu item "Offline Devices" of menu 1 of menu bar item "View" of menu bar 1
    end tell
    """

    public static let consolePrefsPath = ("~/Library/Preferences/Universal Audio/UAD ConsolePrefs.json" as NSString).expandingTildeInPath

    private let runScript: (String) throws -> String
    private let readPreference: () throws -> Bool?
    private let pause: (TimeInterval) -> Void

    public convenience init() {
        self.init(
            runScript: Self.runOnMainThread,
            readPreference: { Self.showOfflineDevices(inConsolePrefs: try Data(contentsOf: URL(fileURLWithPath: Self.consolePrefsPath))) },
            pause: { Thread.sleep(forTimeInterval: $0) }
        )
    }

    init(runScript: @escaping (String) throws -> String, readPreference: @escaping () throws -> Bool?, pause: @escaping (TimeInterval) -> Void) {
        self.runScript = runScript
        self.readPreference = readPreference
        self.pause = pause
    }

    public func isShowingOfflineDevices() throws -> Bool {
        guard let showing = try readPreference() else { throw UADConsoleOfflineDevicesError.preferenceUnreadable }
        return showing
    }

    public func hideOfflineDevices() throws {
        guard try isShowingOfflineDevices() else { return }
        _ = try runScript(Self.clickScript)
        pause(1)
        guard try !isShowingOfflineDevices() else { throw UADConsoleOfflineDevicesError.stillShowing }
    }

    static func showOfflineDevices(inConsolePrefs data: Data) -> Bool? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["settings"] as? [String: Any])?["Show Offline Devices"] as? Bool
    }

    private static func runOnMainThread(_ source: String) throws -> String {
        let (result, error) = runAppleScriptOnMainThread(source)
        if let error {
            throw UADConsoleOfflineDevicesError.scriptFailed(error["NSAppleScriptErrorMessage"] as? String ?? "\(error)")
        }
        return result?.stringValue ?? ""
    }
}
