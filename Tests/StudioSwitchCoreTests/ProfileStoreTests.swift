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
        { "profiles": [ { "name": "Custom", "deviceNameMatch": "X", "audioDeviceName": "Y", "uadConsoleSession": "s", "useIACDriver": true, "daws": [] } ] }
        """
        try json.data(using: .utf8)!.write(to: configURL)
        let store = ProfileStore(configURL: configURL)

        let profiles = try store.loadProfiles()

        XCTAssertEqual(profiles, [Profile(name: "Custom", deviceNameMatch: "X", audioDeviceName: "Y", uadConsoleSession: "s", useIACDriver: true, daws: [])])
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

    func test_save_appendsNewProfileToExistingConfig() throws {
        let configURL = tempDirectory.appendingPathComponent("profiles.json")
        let store = ProfileStore(configURL: configURL)
        _ = try store.loadProfiles()
        let newProfile = Profile(name: "Mobile", deviceNameMatch: "Apollo Twin", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "~/mobile.uadmix", useIACDriver: false, daws: [])

        try store.save(newProfile)

        let profiles = try store.loadProfiles()
        XCTAssertEqual(profiles.map(\.name), ["Home", "Studio", "Mobile"])
    }

    func test_save_replacesExistingProfileWithSameName() throws {
        let configURL = tempDirectory.appendingPathComponent("profiles.json")
        let store = ProfileStore(configURL: configURL)
        _ = try store.loadProfiles()
        let replacement = Profile(name: "Home", deviceNameMatch: "Apollo Twin", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "~/new.uadmix", useIACDriver: true, daws: [])

        try store.save(replacement)

        let profiles = try store.loadProfiles()
        XCTAssertEqual(profiles.map(\.name), ["Home", "Studio"])
        XCTAssertEqual(profiles.first(where: { $0.name == "Home" }), replacement)
    }

    func test_save_createsConfigWhenMissing() throws {
        let configURL = tempDirectory.appendingPathComponent("profiles.json")
        let store = ProfileStore(configURL: configURL)
        let newProfile = Profile(name: "Mobile", deviceNameMatch: "Apollo Twin", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "~/mobile.uadmix", useIACDriver: false, daws: [])

        try store.save(newProfile)

        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        let profiles = try store.loadProfiles()
        XCTAssertEqual(profiles.map(\.name), ["Home", "Studio", "Mobile"])
    }
}
