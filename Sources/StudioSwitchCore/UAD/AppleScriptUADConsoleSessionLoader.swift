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
/// `set frontmost to true` before the keystrokes is load-bearing, not cosmetic: without it the
/// keystrokes don't reliably reach UAD Console (it isn't frontmost yet), and nothing happens —
/// silently, with no error. This used to also send `tell application "UAD Console" to activate`
/// first, sent straight to UAD Console rather than through System Events — verified on real
/// hardware to need its own separate Automation grant (this app controlling "UAD Console"
/// directly), distinct from the System Events grant everything else here relies on, and one that
/// never got authorized (it doesn't even appear as a toggle in System Settings > Automation,
/// unlike System Events, which does). Removed: `set frontmost to true`, sent through System
/// Events like the rest of this script, brings UAD Console forward exactly the same way and only
/// needs the one grant this app already has.
///
/// Also seen on real hardware: the Open panel can fail to close after the final key press (a slow
/// navigation, a focus hiccup) and just sit there — previously that looked like success (no
/// AppleScript error), while `AppleScriptUADConsoleSessionInspector` went on to read the stuck
/// panel's own title ("Choose a session file to open:") back as if it were the loaded session.
/// This now polls for the panel to actually close afterward and raises a real error if it's still
/// open a few seconds later, instead of assuming the four keystrokes landed correctly.
public final class AppleScriptUADConsoleSessionLoader: UADConsoleSessionLoading {
    private let processName: String

    public init(processName: String = "UAD Console") {
        self.processName = processName
    }

    private static let openPanelTitle = "Choose a session file to open:"

    public func loadSession(atPath path: String) throws {
        let source = """
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
                repeat 30 times
                    if not (exists window "\(Self.openPanelTitle)") then exit repeat
                    delay 0.2
                end repeat
                if exists window "\(Self.openPanelTitle)" then error "le panneau d'ouverture ne s'est pas fermé — le chargement a probablement échoué"
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
