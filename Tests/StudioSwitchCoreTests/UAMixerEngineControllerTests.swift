import XCTest
@testable import StudioSwitchCore

/// An in-memory stand-in for the UA Mixer Engine's property tree, answering `get` the way the real
/// engine does on port 4710 (a `data` object with `properties` and `children`).
private final class FakeEngineConnection: UAMixerEngineConnection {
    struct Node {
        var properties: [String: [String: Any]] = [:]
        var children: [String] = []
    }

    var nodes: [String: Node] = [:]
    var ignoresSets = false
    private(set) var sets: [(path: String, value: String)] = []
    private(set) var closed = false

    func get(_ path: String) throws -> [String: Any] {
        guard let node = nodes[path] else { throw UAMixerEngineError.malformedResponse(path) }
        return [
            "properties": node.properties,
            "children": Dictionary(uniqueKeysWithValues: node.children.map { ($0, [String: Any]()) })
        ]
    }

    func set(_ path: String, value: String) throws {
        sets.append((path, value))
        guard !ignoresSets else { return }
        let propertyPath = (path as NSString).deletingLastPathComponent
        let nodePath = (propertyPath as NSString).deletingLastPathComponent
        let key = (propertyPath as NSString).lastPathComponent
        let current = nodes[nodePath]?.properties[key]?["value"]
        let newValue: Any = current is Double ? (Double(value) ?? 0) : value
        nodes[nodePath]?.properties[key]?["value"] = newValue
    }

    func close() { closed = true }

    /// A Solo (online) at index 0 and an offline x8 at index 1, the layout seen at home.
    static func homeLayout(clock: String = "Internal", clockChoices: [String] = ["Internal"], monitorLevel: Double = -28) -> FakeEngineConnection {
        let fake = FakeEngineConnection()
        fake.nodes["/"] = Node(properties: ["ClockSource": ["value": clock, "values": clockChoices]], children: ["devices"])
        fake.nodes["/devices"] = Node(children: ["0", "1"])
        fake.nodes["/devices/0"] = Node(properties: ["DeviceOnline": ["value": true], "DeviceName": ["value": "Apollo Solo"]], children: ["outputs"])
        fake.nodes["/devices/0/outputs"] = Node(children: ["0", "4"])
        fake.nodes["/devices/0/outputs/0"] = Node(properties: ["IOType": ["value": "Headphone"]])
        fake.nodes["/devices/0/outputs/4"] = Node(properties: ["IOType": ["value": "Monitor"], "CRMonitorLevel": ["value": monitorLevel]])
        fake.nodes["/devices/1"] = Node(properties: ["DeviceOnline": ["value": false], "DeviceName": ["value": "Apollo x8"]], children: ["outputs"])
        return fake
    }
}

final class UAMixerEngineControllerTests: XCTestCase {
    private func controller(_ fake: FakeEngineConnection) -> UAMixerEngineController {
        UAMixerEngineController(connect: { fake }, pause: { _ in })
    }

    func test_currentState_readsClockAndMonitorLevelOfTheOnlineDevice() throws {
        let fake = FakeEngineConnection.homeLayout(monitorLevel: -28)

        let state = try controller(fake).currentState()

        XCTAssertEqual(state, UAMixerState(clockSource: "Internal", monitorLevel: -28))
        XCTAssertTrue(fake.closed)
    }

    func test_currentState_skipsOfflineDevicesWhenFindingTheMonitor() throws {
        let fake = FakeEngineConnection.homeLayout()
        fake.nodes["/devices/0"]?.properties["DeviceOnline"] = ["value": false]
        fake.nodes["/devices/1"]?.properties["DeviceOnline"] = ["value": true]
        fake.nodes["/devices/1/outputs"] = FakeEngineConnection.Node(children: ["18"])
        fake.nodes["/devices/1/outputs/18"] = FakeEngineConnection.Node(properties: ["IOType": ["value": "Monitor"], "CRMonitorLevel": ["value": -12.0]])

        let state = try controller(fake).currentState()

        XCTAssertEqual(state.monitorLevel, -12)
    }

    func test_currentState_throwsWhenNoDeviceIsOnline() {
        let fake = FakeEngineConnection.homeLayout()
        fake.nodes["/devices/0"]?.properties["DeviceOnline"] = ["value": false]

        XCTAssertThrowsError(try controller(fake).currentState()) { error in
            XCTAssertEqual(error as? UAMixerEngineError, .noOnlineDevice)
        }
    }

    func test_apply_setsTheMonitorLevelWhenItDiffers() throws {
        let fake = FakeEngineConnection.homeLayout(monitorLevel: -28)

        try controller(fake).apply(clockSource: nil, monitorLevel: -35)

        XCTAssertEqual(fake.sets.map(\.path), ["/devices/0/outputs/4/CRMonitorLevel/value"])
        XCTAssertEqual(fake.sets.map(\.value), ["-35.0"])
    }

    func test_apply_leavesTheMonitorLevelAloneWhenAlreadyRight() throws {
        let fake = FakeEngineConnection.homeLayout(monitorLevel: -35)

        try controller(fake).apply(clockSource: nil, monitorLevel: -35)

        XCTAssertTrue(fake.sets.isEmpty)
    }

    func test_apply_setsTheClockSourceWhenItDiffers() throws {
        let fake = FakeEngineConnection.homeLayout(clock: "ADAT", clockChoices: ["Internal", "ADAT", "Word Clock"])

        try controller(fake).apply(clockSource: "internal", monitorLevel: nil)

        XCTAssertEqual(fake.sets.map(\.path), ["/ClockSource/value"])
        XCTAssertEqual(fake.sets.map(\.value), ["Internal"])
    }

    func test_apply_leavesTheClockAloneWhenAlreadyRight() throws {
        let fake = FakeEngineConnection.homeLayout(clock: "Internal")

        try controller(fake).apply(clockSource: "Internal", monitorLevel: nil)

        XCTAssertTrue(fake.sets.isEmpty)
    }

    func test_apply_throwsWhenTheClockSourceIsNotOffered() {
        let fake = FakeEngineConnection.homeLayout(clock: "ADAT", clockChoices: ["Internal", "ADAT"])

        XCTAssertThrowsError(try controller(fake).apply(clockSource: "S/PDIF", monitorLevel: nil)) { error in
            XCTAssertEqual(error as? UAMixerEngineError, .clockSourceUnavailable("S/PDIF", available: ["Internal", "ADAT"]))
        }
        XCTAssertTrue(fake.sets.isEmpty)
    }

    func test_apply_throwsWhenTheEngineDidNotTakeTheChange() {
        let fake = FakeEngineConnection.homeLayout(monitorLevel: -28)
        fake.ignoresSets = true

        XCTAssertThrowsError(try controller(fake).apply(clockSource: nil, monitorLevel: -35)) { error in
            XCTAssertEqual(error as? UAMixerEngineError, .notApplied("CRMonitorLevel"))
        }
    }

    func test_apply_usesASingleConnection() throws {
        var connections = 0
        let fake = FakeEngineConnection.homeLayout(clock: "ADAT", clockChoices: ["Internal", "ADAT"], monitorLevel: -28)
        let controller = UAMixerEngineController(connect: { connections += 1; return fake }, pause: { _ in })

        try controller.apply(clockSource: "Internal", monitorLevel: -35)

        XCTAssertEqual(connections, 1)
        XCTAssertTrue(fake.closed)
    }

    func test_sessionHasUnsavedChanges_readsTheEnginesDirtyFlag() throws {
        let fake = FakeEngineConnection.homeLayout()
        fake.nodes["/"]?.properties["Dirty"] = ["value": true]

        XCTAssertTrue(try controller(fake).sessionHasUnsavedChanges())

        fake.nodes["/"]?.properties["Dirty"] = ["value": false]
        XCTAssertFalse(try controller(fake).sessionHasUnsavedChanges())
    }
}
