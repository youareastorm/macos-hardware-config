import AppKit

/// A rectangle in global screen coordinates with the origin at the top-left of the main display,
/// y growing downwards — the convention of `CGDisplayBounds` and of System Events' `position`.
public struct WindowFrame: Equatable, CustomStringConvertible {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var description: String { "\(Int(x)),\(Int(y)) \(Int(width))×\(Int(height))" }
}

public enum WindowPlacement {
    private static let tolerance = 1.0

    /// Where to put `window` so it's entirely inside `area`: its top-left corner, shrunk only if it's
    /// bigger than the area. `nil` when it's already entirely inside, so a window placed by hand on
    /// the right screen keeps its exact spot.
    public static func target(for window: WindowFrame, inside area: WindowFrame) -> WindowFrame? {
        let inside = window.x >= area.x - tolerance
            && window.y >= area.y - tolerance
            && window.x + window.width <= area.x + area.width + tolerance
            && window.y + window.height <= area.y + area.height + tolerance
        guard !inside else { return nil }
        return WindowFrame(x: area.x, y: area.y, width: min(window.width, area.width), height: min(window.height, area.height))
    }
}

public enum UADConsoleWindowOutcome: Equatable {
    case alreadyThere
    case moved(from: WindowFrame, to: WindowFrame)
    case noBuiltInDisplay
}

public enum UADConsoleWindowError: Error, Equatable {
    case windowNotFound
    case scriptFailed(String)
}

public protocol UADConsoleWindowPlacing {
    func ensureOnBuiltInDisplay() throws -> UADConsoleWindowOutcome
}

/// Keeps UAD Console's main window on the MacBook's own screen, whichever display macOS marks as
/// main (at home and at the studio an external monitor is main, and Console reopens there).
/// Moved with System Events, like the session switch (same Accessibility permission).
public final class UADConsoleWindowPlacer: UADConsoleWindowPlacing {
    private let builtInArea: () -> WindowFrame?
    private let readWindow: () throws -> WindowFrame?
    private let moveWindow: (WindowFrame) throws -> Void

    public convenience init() {
        self.init(builtInArea: Self.builtInDisplayArea, readWindow: Self.readConsoleWindow, moveWindow: Self.moveConsoleWindow)
    }

    init(builtInArea: @escaping () -> WindowFrame?, readWindow: @escaping () throws -> WindowFrame?, moveWindow: @escaping (WindowFrame) throws -> Void) {
        self.builtInArea = builtInArea
        self.readWindow = readWindow
        self.moveWindow = moveWindow
    }

    public func ensureOnBuiltInDisplay() throws -> UADConsoleWindowOutcome {
        guard let area = builtInArea() else { return .noBuiltInDisplay }
        guard let window = try readWindow() else { throw UADConsoleWindowError.windowNotFound }
        guard let target = WindowPlacement.target(for: window, inside: area) else { return .alreadyThere }
        try moveWindow(target)
        return .moved(from: window, to: target)
    }

    /// The built-in display's usable area (without the menu bar, when it has one), converted from
    /// AppKit's bottom-left coordinates to the top-left ones System Events uses.
    static func builtInDisplayArea() -> WindowFrame? {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let builtIn = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }
        guard let visible = builtIn?.visibleFrame else { return nil }
        return WindowFrame(x: visible.minX, y: mainHeight - visible.maxY, width: visible.width, height: visible.height)
    }

    private static let mainWindow = #"first window of process "UAD Console" whose subrole is "AXStandardWindow""#

    static func readConsoleWindow() throws -> WindowFrame? {
        let source = """
        tell application "System Events"
            if not (exists process "UAD Console") then return ""
            if not (exists \(mainWindow)) then return ""
            set {x, y} to position of \(mainWindow)
            set {w, h} to size of \(mainWindow)
            return (x as text) & "," & (y as text) & "," & (w as text) & "," & (h as text)
        end tell
        """
        let (result, error) = runAppleScriptOnMainThread(source)
        if let error { throw UADConsoleWindowError.scriptFailed(error["NSAppleScriptErrorMessage"] as? String ?? "\(error)") }
        let numbers = (result?.stringValue ?? "").split(separator: ",").compactMap { Double($0) }
        guard numbers.count == 4 else { return nil }
        return WindowFrame(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    static func moveConsoleWindow(to frame: WindowFrame) throws {
        let source = """
        tell application "System Events"
            set position of \(mainWindow) to {\(Int(frame.x)), \(Int(frame.y))}
            set size of \(mainWindow) to {\(Int(frame.width)), \(Int(frame.height))}
        end tell
        """
        let (_, error) = runAppleScriptOnMainThread(source)
        if let error { throw UADConsoleWindowError.scriptFailed(error["NSAppleScriptErrorMessage"] as? String ?? "\(error)") }
    }
}
