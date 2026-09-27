import Foundation

/// UAD Console ignores a request to open a different session file while it's already running —
/// tried and empirically ruled out on real hardware (Apollo Solo + UAD Console): a second
/// `NSWorkspace.open(fileURL:withApplicationAt:)` leaves the window title unchanged, a direct Apple
/// Event `open` sent to the app does the same, and asking it to `quit` via AppleScript is refused
/// (error -128). The only approach that worked, verified twice in both directions (the window
/// title going from "UAD Console: empty home" to "UAD Console: home guit vox" and back), is driving
/// UAD Console's own File > Open... menu through System Events, then typing the path into the
/// standard open panel via its "Go to Folder" shortcut (Cmd+Shift+G).
///
/// `activate` and `set frontmost to true` before the keystrokes are load-bearing, not cosmetic:
/// without them the keystrokes don't reliably reach UAD Console (it isn't frontmost yet), and
/// nothing happens — silently, with no error.
public final class AppleScriptUADConsoleSessionLoader: UADConsoleSessionLoading {
    private let processName: String

    public init(processName: String = "UAD Console") {
        self.processName = processName
    }

    public func loadSession(atPath path: String) throws {
        let source = """
        tell application "UAD Console" to activate
        delay 0.5
        tell application "System Events"
            tell process "\(Self.escaped(processName))"
                set frontmost to true
                click menu item "Open..." of menu "File" of menu bar 1
                delay 0.6
                keystroke "g" using {command down, shift down}
                delay 0.6
                keystroke "\(Self.escaped(path))"
                delay 0.3
                key code 36
                delay 1
                key code 36
            end tell
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            throw UADConsoleSessionLoaderError.appleScriptFailed("could not parse AppleScript source")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw UADConsoleSessionLoaderError.appleScriptFailed("\(errorInfo)")
        }
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
