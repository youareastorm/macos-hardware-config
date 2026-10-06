import XCTest
@testable import StudioSwitchCore

/// Plays UAD Console's View > Offline Devices menu item: answers the read script with the
/// current check mark and flips it when the click script runs.
private final class FakeConsoleMenu {
    var checked: Bool
    var clickWorks = true
    private(set) var clicks = 0

    init(checked: Bool) { self.checked = checked }

    func run(_ script: String) throws -> String {
        if script.contains("click menu item") {
            clicks += 1
            if clickWorks { checked.toggle() }
        }
        return ""
    }

    /// What `ConsolePrefs.json` holds: Console rewrites it as soon as the item is clicked.
    func preference() throws -> Bool? { checked }
}

final class UADConsoleOfflineDevicesControllerTests: XCTestCase {
    private func controller(_ menu: FakeConsoleMenu) -> AppleScriptUADConsoleOfflineDevicesController {
        AppleScriptUADConsoleOfflineDevicesController(runScript: menu.run, readPreference: menu.preference, pause: { _ in })
    }

    func test_isShowingOfflineDevices_followsConsolesPreference() throws {
        XCTAssertTrue(try controller(FakeConsoleMenu(checked: true)).isShowingOfflineDevices())
        XCTAssertFalse(try controller(FakeConsoleMenu(checked: false)).isShowingOfflineDevices())
    }

    func test_hideOfflineDevices_clicksTheItemWhenChecked() throws {
        let menu = FakeConsoleMenu(checked: true)

        try controller(menu).hideOfflineDevices()

        XCTAssertEqual(menu.clicks, 1)
        XCTAssertFalse(menu.checked)
    }

    func test_hideOfflineDevices_doesNotClickWhenAlreadyHidden() throws {
        let menu = FakeConsoleMenu(checked: false)

        try controller(menu).hideOfflineDevices()

        XCTAssertEqual(menu.clicks, 0)
        XCTAssertFalse(menu.checked)
    }

    func test_hideOfflineDevices_throwsWhenTheClickDidNotTakeEffect() {
        let menu = FakeConsoleMenu(checked: true)
        menu.clickWorks = false

        XCTAssertThrowsError(try controller(menu).hideOfflineDevices()) { error in
            XCTAssertEqual(error as? UADConsoleOfflineDevicesError, .stillShowing)
        }
    }

    func test_isShowingOfflineDevices_throwsWhenThePreferenceIsMissing() {
        let controller = AppleScriptUADConsoleOfflineDevicesController(runScript: { _ in "" }, readPreference: { nil }, pause: { _ in })

        XCTAssertThrowsError(try controller.isShowingOfflineDevices()) { error in
            XCTAssertEqual(error as? UADConsoleOfflineDevicesError, .preferenceUnreadable)
        }
    }

    func test_preferenceValue_readsShowOfflineDevicesFromConsolePrefs() {
        let json = Data(#"{"header": {"version": "1.0"}, "settings": {"Show Offline Devices": true, "launched": 176}}"#.utf8)

        XCTAssertEqual(AppleScriptUADConsoleOfflineDevicesController.showOfflineDevices(inConsolePrefs: json), true)
        XCTAssertNil(AppleScriptUADConsoleOfflineDevicesController.showOfflineDevices(inConsolePrefs: Data("{}".utf8)))
    }
}
