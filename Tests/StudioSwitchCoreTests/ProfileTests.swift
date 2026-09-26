import XCTest
@testable import StudioSwitchCore

final class ProfileTests: XCTestCase {
    func test_decodesProfilesFileFromJSON() throws {
        let json = """
        {
          "profiles": [
            {
              "name": "Home",
              "deviceNameMatch": "Apollo Solo",
              "audioDeviceName": "Universal Audio Thunderbolt",
              "uadConsoleSession": "~/Documents/Universal Audio/Sessions/home guit vox.uadmix",
              "useIACDriver": false,
              "daws": [
                { "name": "Logic Pro", "bundleID": "com.apple.logic10", "appPath": null, "templatePath": null }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ProfilesFile.self, from: json)

        XCTAssertEqual(decoded.profiles.count, 1)
        XCTAssertEqual(decoded.profiles[0].name, "Home")
        XCTAssertEqual(decoded.profiles[0].deviceNameMatch, "Apollo Solo")
        XCTAssertEqual(decoded.profiles[0].audioDeviceName, "Universal Audio Thunderbolt")
        XCTAssertEqual(decoded.profiles[0].daws[0].bundleID, "com.apple.logic10")
        XCTAssertNil(decoded.profiles[0].daws[0].appPath)
        XCTAssertNil(decoded.profiles[0].daws[0].templatePath)
        XCTAssertNil(decoded.profiles[0].expectedSampleRate)
        XCTAssertEqual(decoded.profiles[0].expectedExternalDiskNames, [])
    }

    func test_decodesExpectedSampleRateAndExternalDisksWhenPresent() throws {
        let json = """
        {
          "name": "Studio",
          "deviceNameMatch": "Apollo",
          "audioDeviceName": "Universal Audio Thunderbolt",
          "uadConsoleSession": "s",
          "useIACDriver": false,
          "daws": [],
          "expectedSampleRate": 96000,
          "expectedExternalDiskNames": ["Backup", "Samples"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Profile.self, from: json)

        XCTAssertEqual(decoded.expectedSampleRate, 96000)
        XCTAssertEqual(decoded.expectedExternalDiskNames, ["Backup", "Samples"])
    }

    func test_roundTripsThroughEncodingAndDecoding() throws {
        let profile = Profile(
            name: "Studio",
            deviceNameMatch: "Apollo",
            audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s",
            useIACDriver: true,
            daws: [DAWEntry(name: "Pro Tools", bundleID: "com.avid.ProTools", templatePath: nil)],
            expectedSampleRate: 96000,
            expectedExternalDiskNames: ["Backup"]
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)

        XCTAssertEqual(decoded, profile)
    }
}
