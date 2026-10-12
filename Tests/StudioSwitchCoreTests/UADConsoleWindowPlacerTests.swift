import XCTest
@testable import StudioSwitchCore

final class UADConsoleWindowPlacerTests: XCTestCase {
    // The studio layout seen on 2026-10-12: a 3440×1440 main display, the MacBook's screen to its right.
    private let builtIn = WindowFrame(x: 3440, y: 540, width: 1440, height: 900)

    func test_target_isNilWhenTheWindowIsAlreadyOnTheBuiltInDisplay() {
        XCTAssertNil(WindowPlacement.target(for: WindowFrame(x: 3440, y: 570, width: 1440, height: 870), inside: builtIn))
    }

    func test_target_movesAWindowFromTheExternalDisplayToTheTopLeftOfTheBuiltInOne() {
        let target = WindowPlacement.target(for: WindowFrame(x: 200, y: 100, width: 1440, height: 870), inside: builtIn)

        XCTAssertEqual(target, WindowFrame(x: 3440, y: 540, width: 1440, height: 870))
    }

    func test_target_shrinksAWindowTooBigForTheBuiltInDisplay() {
        let target = WindowPlacement.target(for: WindowFrame(x: 0, y: 0, width: 2000, height: 1200), inside: builtIn)

        XCTAssertEqual(target, WindowFrame(x: 3440, y: 540, width: 1440, height: 900))
    }

    func test_target_movesAWindowThatOnlyPartlyOverlapsTheBuiltInDisplay() {
        XCTAssertNotNil(WindowPlacement.target(for: WindowFrame(x: 3000, y: 600, width: 1440, height: 800), inside: builtIn))
    }

    func test_ensureOnBuiltInDisplay_movesTheWindowAndSaysSo() throws {
        var moved: WindowFrame?
        let placer = UADConsoleWindowPlacer(
            builtInArea: { self.builtIn },
            readWindow: { WindowFrame(x: 200, y: 100, width: 1440, height: 870) },
            moveWindow: { moved = $0 }
        )

        let outcome = try placer.ensureOnBuiltInDisplay()

        XCTAssertEqual(moved, WindowFrame(x: 3440, y: 540, width: 1440, height: 870))
        XCTAssertEqual(outcome, .moved(from: WindowFrame(x: 200, y: 100, width: 1440, height: 870), to: WindowFrame(x: 3440, y: 540, width: 1440, height: 870)))
    }

    func test_ensureOnBuiltInDisplay_leavesAWellPlacedWindowAlone() throws {
        var moved = false
        let placer = UADConsoleWindowPlacer(
            builtInArea: { self.builtIn },
            readWindow: { WindowFrame(x: 3500, y: 600, width: 1200, height: 700) },
            moveWindow: { _ in moved = true }
        )

        XCTAssertEqual(try placer.ensureOnBuiltInDisplay(), .alreadyThere)
        XCTAssertFalse(moved)
    }

    func test_ensureOnBuiltInDisplay_doesNothingWithoutABuiltInDisplay() throws {
        var moved = false
        let placer = UADConsoleWindowPlacer(builtInArea: { nil }, readWindow: { WindowFrame(x: 0, y: 0, width: 100, height: 100) }, moveWindow: { _ in moved = true })

        XCTAssertEqual(try placer.ensureOnBuiltInDisplay(), .noBuiltInDisplay)
        XCTAssertFalse(moved)
    }

    func test_ensureOnBuiltInDisplay_throwsWhenTheWindowCannotBeFound() {
        let placer = UADConsoleWindowPlacer(builtInArea: { self.builtIn }, readWindow: { nil }, moveWindow: { _ in })

        XCTAssertThrowsError(try placer.ensureOnBuiltInDisplay()) { error in
            XCTAssertEqual(error as? UADConsoleWindowError, .windowNotFound)
        }
    }
}
