import Foundation

/// One open connection to the UA Mixer Engine's local control interface (TCP port 4710, the one
/// UA's own remote apps use). `get` returns the `data` object of the engine's reply: a
/// `properties` dictionary (each entry holding `value`, sometimes `values`) and a `children`
/// dictionary keyed by child name.
public protocol UAMixerEngineConnection: AnyObject {
    func get(_ path: String) throws -> [String: Any]
    func set(_ path: String, value: String) throws
    func close()
}

public enum UAMixerEngineError: Error, Equatable {
    case connectionFailed(String)
    case timedOut(String)
    case malformedResponse(String)
    case noOnlineDevice
    case noMonitorOutput(String)
    case clockSourceUnavailable(String, available: [String])
    case notApplied(String)
}

public struct UAMixerState: Equatable {
    public let clockSource: String
    public let monitorLevel: Double

    public init(clockSource: String, monitorLevel: Double) {
        self.clockSource = clockSource
        self.monitorLevel = monitorLevel
    }
}

public protocol UAMixerControlling {
    func currentState() throws -> UAMixerState
    /// Sets whichever of the two is given, only when it differs from the current value, then reads
    /// it back to confirm the engine took it.
    func apply(clockSource: String?, monitorLevel: Double?) throws
}

/// Reads and writes the clock source and the monitor level through the UA Mixer Engine — the
/// values UAD Console shows in its bottom bar and on its MONITOR knob (verified on an Apollo Solo:
/// setting `CRMonitorLevel` to -35 moved Console's knob to -35.0 dB).
///
/// Every call uses a single connection: the engine (11.9.0) crashed with a segfault in
/// `Ntwk_Socket_Server::createConnectionObject` when it was sent a burst of short-lived
/// connections.
public final class UAMixerEngineController: UAMixerControlling {
    private static let monitorLevelTolerance = 0.25

    private let connect: () throws -> UAMixerEngineConnection
    private let pause: (TimeInterval) -> Void

    public init(
        connect: @escaping () throws -> UAMixerEngineConnection = { try TCPUAMixerEngineConnection() },
        pause: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.connect = connect
        self.pause = pause
    }

    public func currentState() throws -> UAMixerState {
        try withConnection { connection in
            UAMixerState(
                clockSource: try clockSource(connection),
                monitorLevel: try monitorLevel(connection, at: try monitorOutputPath(connection))
            )
        }
    }

    /// The engine's `Dirty` flag: the open UAD Console session has unsaved changes.
    public func sessionHasUnsavedChanges() throws -> Bool {
        try withConnection { connection in
            Self.propertyValue("Dirty", in: try connection.get("/")) as? Bool ?? false
        }
    }

    public func apply(clockSource wanted: String?, monitorLevel wantedLevel: Double?) throws {
        try withConnection { connection in
            if let wanted {
                try applyClockSource(wanted, connection)
            }
            if let wantedLevel {
                try applyMonitorLevel(wantedLevel, connection)
            }
        }
    }

    private func applyClockSource(_ wanted: String, _ connection: UAMixerEngineConnection) throws {
        let root = try connection.get("/")
        let current = Self.propertyValue("ClockSource", in: root) as? String
        if current?.caseInsensitiveCompare(wanted) == .orderedSame { return }

        let available = Self.property("ClockSource", in: root)?["values"] as? [String] ?? []
        guard let choice = available.first(where: { $0.caseInsensitiveCompare(wanted) == .orderedSame }) else {
            throw UAMixerEngineError.clockSourceUnavailable(wanted, available: available)
        }
        try connection.set("/ClockSource/value", value: choice)
        pause(0.5)
        guard try clockSource(connection).caseInsensitiveCompare(choice) == .orderedSame else {
            throw UAMixerEngineError.notApplied("ClockSource")
        }
    }

    private func applyMonitorLevel(_ wanted: Double, _ connection: UAMixerEngineConnection) throws {
        let outputPath = try monitorOutputPath(connection)
        if abs(try monitorLevel(connection, at: outputPath) - wanted) < Self.monitorLevelTolerance { return }

        try connection.set("\(outputPath)/CRMonitorLevel/value", value: "\(wanted)")
        pause(0.5)
        guard abs(try monitorLevel(connection, at: outputPath) - wanted) < Self.monitorLevelTolerance else {
            throw UAMixerEngineError.notApplied("CRMonitorLevel")
        }
    }

    private func withConnection<T>(_ body: (UAMixerEngineConnection) throws -> T) throws -> T {
        let connection = try connect()
        defer { connection.close() }
        return try body(connection)
    }

    private func clockSource(_ connection: UAMixerEngineConnection) throws -> String {
        guard let value = Self.propertyValue("ClockSource", in: try connection.get("/")) as? String else {
            throw UAMixerEngineError.malformedResponse("/ ClockSource")
        }
        return value
    }

    private func monitorLevel(_ connection: UAMixerEngineConnection, at outputPath: String) throws -> Double {
        guard let value = Self.propertyValue("CRMonitorLevel", in: try connection.get(outputPath)) as? Double else {
            throw UAMixerEngineError.malformedResponse("\(outputPath) CRMonitorLevel")
        }
        return value
    }

    /// The MONITOR output of the first online unit: an offline unit (e.g. the studio's x8 when at
    /// home) is still listed by the engine but has nothing to control.
    private func monitorOutputPath(_ connection: UAMixerEngineConnection) throws -> String {
        for device in Self.sortedChildren(of: try connection.get("/devices")) {
            let devicePath = "/devices/\(device)"
            guard Self.propertyValue("DeviceOnline", in: try connection.get(devicePath)) as? Bool == true else { continue }
            for output in Self.sortedChildren(of: try connection.get("\(devicePath)/outputs")) {
                let outputPath = "\(devicePath)/outputs/\(output)"
                if Self.propertyValue("IOType", in: try connection.get(outputPath)) as? String == "Monitor" {
                    return outputPath
                }
            }
            throw UAMixerEngineError.noMonitorOutput(devicePath)
        }
        throw UAMixerEngineError.noOnlineDevice
    }

    private static func property(_ key: String, in data: [String: Any]) -> [String: Any]? {
        (data["properties"] as? [String: Any])?[key] as? [String: Any]
    }

    private static func propertyValue(_ key: String, in data: [String: Any]) -> Any? {
        property(key, in: data)?["value"]
    }

    private static func sortedChildren(of data: [String: Any]) -> [String] {
        let names = (data["children"] as? [String: Any])?.keys.map { $0 } ?? []
        return names.sorted { (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1) }
    }
}
