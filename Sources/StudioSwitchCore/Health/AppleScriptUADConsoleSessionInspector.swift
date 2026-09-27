import Foundation

/// Reads UAD Console's front window title via Apple Events (System Events), since CoreAudio has
/// no notion of "which session a third-party app has open". Requires two separate permissions on
/// the user's end, verified on real hardware after this silently returned nil for a while despite
/// Automation being granted: (1) Automation, to let this app send Apple Events to System Events at
/// all, and (2) Accessibility, which System Events itself needs on this app's behalf to inspect
/// another app's UI elements (`exists window 1 of process "UAD Console"`) — without it, System
/// Events returns the exact error "n'est pas autorisé à un accès d'aide" ("not authorized for
/// assistive access"), swallowed here into a plain nil. Rebuilding the app with a new ad-hoc
/// signature can silently invalidate a previously granted Accessibility permission for it; when
/// that happens, toggling the entry off/on in Accessibility settings is not enough to re-arm it —
/// it has to be removed (the "−" button) and re-granted from scratch.
public final class AppleScriptUADConsoleSessionInspector: UADConsoleSessionInspecting {
    private let processName: String

    public init(processName: String = "UAD Console") {
        self.processName = processName
    }

    public func currentSessionName() -> String? {
        let source = """
        tell application "System Events"
            if not (exists process "\(processName)") then return ""
            tell process "\(processName)"
                if not (exists window 1) then return ""
                return name of window 1
            end tell
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else { return nil }
        let value = result.stringValue ?? ""
        return value.isEmpty ? nil : value
    }
}
