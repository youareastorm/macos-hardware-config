import Foundation

/// The UA Mixer Engine's wire format: plain-text commands (`get <path>`, `set <path>/value <v>`)
/// and JSON replies, each terminated by a null byte. Replies can arrive split or several at once.
struct UAMixerEngineFraming {
    private var buffer = Data()

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    mutating func nextMessage() -> [String: Any]? {
        while let end = buffer.firstIndex(of: 0) {
            let message = buffer[buffer.startIndex..<end]
            buffer = Data(buffer[buffer.index(after: end)...])
            if let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any] {
                return object
            }
        }
        return nil
    }

    static func command(_ parts: String...) -> Data {
        Data((parts.joined(separator: " ") + "\0").utf8)
    }
}

/// A blocking connection to the UA Mixer Engine on 127.0.0.1:4710. Meant to be opened once per
/// batch of operations and closed right after (see `UAMixerEngineController`).
public final class TCPUAMixerEngineConnection: UAMixerEngineConnection {
    private let socketDescriptor: Int32
    private var framing = UAMixerEngineFraming()
    private var isClosed = false

    public init(port: UInt16 = 4710, timeout: TimeInterval = 3) throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw UAMixerEngineError.connectionFailed("socket() a échoué") }

        var time = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            Darwin.close(descriptor)
            throw UAMixerEngineError.connectionFailed("moteur UA injoignable sur le port \(port)")
        }
        socketDescriptor = descriptor
    }

    deinit {
        close()
    }

    public func get(_ path: String) throws -> [String: Any] {
        try send(UAMixerEngineFraming.command("get", path))
        while true {
            let message = try receiveMessage(for: path)
            // The engine also pushes unrelated updates on the same connection; skip them.
            guard message["path"] as? String == path else { continue }
            guard let data = message["data"] as? [String: Any] else {
                throw UAMixerEngineError.malformedResponse(path)
            }
            return data
        }
    }

    public func set(_ path: String, value: String) throws {
        try send(UAMixerEngineFraming.command("set", path, value))
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        Darwin.close(socketDescriptor)
    }

    private func send(_ data: Data) throws {
        let sent = data.withUnsafeBytes { Darwin.send(socketDescriptor, $0.baseAddress, data.count, 0) }
        guard sent == data.count else { throw UAMixerEngineError.connectionFailed("envoi au moteur UA impossible") }
    }

    private func receiveMessage(for path: String) throws -> [String: Any] {
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            if let message = framing.nextMessage() { return message }
            let count = recv(socketDescriptor, &chunk, chunk.count, 0)
            if count < 0 { throw UAMixerEngineError.timedOut(path) }
            if count == 0 { throw UAMixerEngineError.connectionFailed("le moteur UA a fermé la connexion") }
            framing.append(Data(chunk[0..<count]))
        }
    }
}
