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
/// silently, with no error. It also needs a short delay right after it, verified on real hardware:
/// clicking the File menu immediately (no delay) sometimes lands before UAD Console has actually
/// finished coming forward, and the whole rest of the script then silently no-ops — same failure
/// mode, no AppleScript error, just nothing happening. This used to also send `tell application
/// "UAD Console" to activate`
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

    public func loadSession(atPath path: String, discardingUnsavedChanges: Bool) throws {
        let sessionName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let source = """
        tell application "System Events"
            tell process "\(Self.escaped(processName))"
                set frontmost to true
                delay 0.5
                click menu item "Open..." of menu "File" of menu bar 1
                \(discardingUnsavedChanges ? Self.dismissSaveQuestion : "")
                set waited to 0
                repeat until (exists window "\(Self.openPanelTitle)")
                    delay 0.25
                    set waited to waited + 0.25
                    if waited > 20 then error "le panneau d'ouverture ne s'est pas affiché"
                end repeat
                delay 0.8

                keystroke "g" using {command down, shift down}
                delay 1.2
                keystroke "\(Self.escaped(path))"
                delay 0.5
                key code 36
                delay 1.5
                key code 36

                set waited to 0
                repeat while (exists window "\(Self.openPanelTitle)")
                    delay 0.25
                    set waited to waited + 0.25
                    if waited > 15 then error "le panneau d'ouverture ne s'est pas fermé"
                end repeat

                set waited to 0
                repeat until ((count of (windows whose name begins with "UAD Console:" and name contains "\(Self.escaped(sessionName))")) > 0)
                    delay 0.25
                    set waited to waited + 0.25
                    if waited > 20 then error "la session \(Self.escaped(sessionName)) ne s'est pas chargée"
                end repeat
            end tell
        end tell
        """

        let (_, error) = runAppleScriptOnMainThread(source)
        if let error {
            throw UADConsoleSessionLoaderError.appleScriptFailed("\(error)")
        }
    }

    /// With unsaved changes, File > Open... first shows UAD Console's own "save changes?" question
    /// (logged by Console as `Rack_Question`, with a `dont_save` button). It's drawn by Console
    /// itself, not a macOS window, so System Events can't see or click it. Verified twice on real
    /// hardware (UAD Console 1.3.1): Escape closes it *without saving* (the session file stayed
    /// byte-identical, the engine's `Dirty` flag went false) and the Open panel follows. Escape is
    /// only sent if the panel isn't already there, so it can't cancel the panel itself.
    private static let dismissSaveQuestion = """
    delay 1.5
                    if not (exists window "\(openPanelTitle)") then key code 53
    """

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
