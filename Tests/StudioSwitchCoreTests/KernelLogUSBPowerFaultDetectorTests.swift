import XCTest
@testable import StudioSwitchCore

private final class MockUSBKernelLogInspector: USBKernelLogInspecting {
    var lines: [String] = []
    private(set) var requestedWindow: TimeInterval?

    func recentUSBKernelEvents(within window: TimeInterval) -> [String] {
        requestedWindow = window
        return lines
    }
}

final class KernelLogUSBPowerFaultDetectorTests: XCTestCase {
    func test_recentPowerIncidents_matchesExplicitPowerWording() {
        let logInspector = MockUSBKernelLogInspector()
        logInspector.lines = ["kernel: AppleUSBHostPort: not enough power available"]
        let detector = KernelLogUSBPowerFaultDetector(logInspector: logInspector)

        let incidents = detector.recentPowerIncidents(within: 900)

        XCTAssertEqual(incidents, [USBPowerIncident(line: "kernel: AppleUSBHostPort: not enough power available")])
    }

    func test_recentPowerIncidents_matchesDetachChurnWithoutMentioningPower() {
        let logInspector = MockUSBKernelLogInspector()
        logInspector.lines = ["kernel: Netac MobileDataStar detached"]
        let detector = KernelLogUSBPowerFaultDetector(logInspector: logInspector)

        let incidents = detector.recentPowerIncidents(within: 900)

        XCTAssertEqual(incidents.count, 1)
    }

    func test_recentPowerIncidents_ignoresUnrelatedLines() {
        let logInspector = MockUSBKernelLogInspector()
        logInspector.lines = ["kernel: Bluetooth connection established", "kernel: Wi-Fi roam scan complete"]
        let detector = KernelLogUSBPowerFaultDetector(logInspector: logInspector)

        XCTAssertEqual(detector.recentPowerIncidents(within: 900), [])
    }

    func test_recentPowerIncidents_passesWindowThrough() {
        let logInspector = MockUSBKernelLogInspector()
        let detector = KernelLogUSBPowerFaultDetector(logInspector: logInspector)

        _ = detector.recentPowerIncidents(within: 300)

        XCTAssertEqual(logInspector.requestedWindow, 300)
    }
}
