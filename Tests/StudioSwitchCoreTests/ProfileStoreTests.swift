import XCTest
@testable import StudioSwitchCore

final class ProfileStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func test_loadProfiles_createsDefaultConfigWhenMissing() throws {
        let configURL = tempDirectory.appendingPathComponent("profiles.json")
        let store = ProfileStore(configURL: configURL)

        let profiles = try store.loadProfiles()

        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        XCTAssertEqual(profiles.map(\.name), ["Home", "Studio"])
    }

    func test_loadProfiles_readsExistingConfig() throws {
        let configURL = tempDirectory.appendingPathComponent("profiles.json")
        let json = """
        { "profiles": [ { "name": "Custom", "deviceNameMatch": "X", "uadConsoleSession": "s", "useIACDriver": true, "daws": [] } ] }
        """
        try json.data(using: .utf8)!.write(to: configURL)
        let store = ProfileStore(configURL: configURL)

        let profiles = try store.loadProfiles()

        XCTAssertEqual(profiles, [Profile(name: "Custom", deviceNameMatch: "X", uadConsoleSession: "s", useIACDriver: true, daws: [])])
    }

    func test_loadProfiles_throwsOnMalformedJSON() throws {
        let configURL = tempDirectory.appendingPathComponent("profiles.json")
        try "not json".data(using: .utf8)!.write(to: configURL)
        let store = ProfileStore(configURL: configURL)

        XCTAssertThrowsError(try store.loadProfiles()) { error in
            guard case ProfileStoreError.decodingFailed = error else {
                return XCTFail("expected decodingFailed, got \(error)")
            }
        }
    }
}
