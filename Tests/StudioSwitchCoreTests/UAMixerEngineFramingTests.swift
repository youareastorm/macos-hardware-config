import XCTest
@testable import StudioSwitchCore

final class UAMixerEngineFramingTests: XCTestCase {
    func test_nextMessage_waitsForTheNullTerminator() {
        var framing = UAMixerEngineFraming()
        framing.append(Data(#"{"path": "/", "da"#.utf8))

        XCTAssertNil(framing.nextMessage())
    }

    func test_nextMessage_returnsEachCompleteMessageInOrder() throws {
        var framing = UAMixerEngineFraming()
        framing.append(Data((#"{"path": "/a", "data": {}}"# + "\0" + #"{"path": "/b", "data": {"x": 1}}"# + "\0").utf8))

        XCTAssertEqual(framing.nextMessage()?["path"] as? String, "/a")
        XCTAssertEqual(framing.nextMessage()?["path"] as? String, "/b")
        XCTAssertNil(framing.nextMessage())
    }

    func test_nextMessage_keepsAPartialMessageForLater() {
        var framing = UAMixerEngineFraming()
        framing.append(Data((#"{"path": "/a", "data": {}}"# + "\0" + #"{"path": "/b""#).utf8))

        XCTAssertEqual(framing.nextMessage()?["path"] as? String, "/a")
        XCTAssertNil(framing.nextMessage())

        framing.append(Data((#", "data": {}}"# + "\0").utf8))
        XCTAssertEqual(framing.nextMessage()?["path"] as? String, "/b")
    }

    func test_command_isNullTerminated() {
        XCTAssertEqual(UAMixerEngineFraming.command("get", "/devices"), Data("get /devices\0".utf8))
        XCTAssertEqual(UAMixerEngineFraming.command("set", "/ClockSource/value", "Internal"), Data("set /ClockSource/value Internal\0".utf8))
    }
}
