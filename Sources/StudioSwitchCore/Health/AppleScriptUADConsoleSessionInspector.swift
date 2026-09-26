import Foundation

/// Reads UAD Console's front window title via Apple Events (System Events), since CoreAudio has
/// no notion of "which session a third-party app has open". Requires Automation permission for
/// this app to control System Events, granted on first use via the macOS permission prompt.
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
