import Foundation

public final class ThunderboltHardwareModelProvider: HardwareModelProviding {
    public init() {}

    public func connectedModelNames() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPThunderboltDataType"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output
            .components(separatedBy: .newlines)
            .compactMap { line in
                guard let range = line.range(of: "Device Name: ") else { return nil }
                return line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            }
    }
}
