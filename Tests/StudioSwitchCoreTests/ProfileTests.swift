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
    }

    func test_decodesExpectedSampleRateWhenPresent() throws {
        let json = """
        {
          "name": "Studio",
          "deviceNameMatch": "Apollo",
          "audioDeviceName": "Universal Audio Thunderbolt",
          "uadConsoleSession": "s",
          "daws": [],
          "expectedSampleRate": 96000
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Profile.self, from: json)

        XCTAssertEqual(decoded.expectedSampleRate, 96000)
    }

    func test_roundTripsThroughEncodingAndDecoding() throws {
        let profile = Profile(
            name: "Studio",
            deviceNameMatch: "Apollo",
            audioDeviceName: "Universal Audio Thunderbolt",
            uadConsoleSession: "s",
            daws: [DAWEntry(name: "Pro Tools", bundleID: "com.avid.ProTools", templatePath: nil)],
            expectedSampleRate: 96000
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)

        XCTAssertEqual(decoded, profile)
    }

    func test_decodesUADMixerSettingsWhenPresent() throws {
        let json = """
        {
          "name": "Studio",
          "deviceNameMatch": "Thunderbolt 3 Option Card",
          "audioDeviceName": "Universal Audio Thunderbolt",
          "uadConsoleSession": "s",
          "daws": [],
          "expectedClockSource": "Internal",
          "expectedMonitorLevel": 0,
          "hideUADOfflineDevices": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Profile.self, from: json)

        XCTAssertEqual(decoded.expectedClockSource, "Internal")
        XCTAssertEqual(decoded.expectedMonitorLevel, 0)
        XCTAssertTrue(decoded.hideUADOfflineDevices)
    }

    func test_uadMixerSettingsDefaultToLeavingThingsAlone() throws {
        let json = """
        {"name": "Home", "deviceNameMatch": "Apollo Solo", "audioDeviceName": "Universal Audio Thunderbolt",
         "uadConsoleSession": "s", "daws": []}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Profile.self, from: json)

        XCTAssertNil(decoded.expectedClockSource)
        XCTAssertNil(decoded.expectedMonitorLevel)
        XCTAssertFalse(decoded.hideUADOfflineDevices)
    }

    func test_dawEntry_decodesItsIconWhenPresent() throws {
        let json = #"{"name": "Cubase 15", "bundleID": "com.steinberg.cubase15", "icon": "cubase"}"#.data(using: .utf8)!

        let daw = try JSONDecoder().decode(DAWEntry.self, from: json)

        XCTAssertEqual(daw.icon, "cubase")
        XCTAssertNil(daw.templatePath)
    }

    func test_dawEntry_iconIsOptional() throws {
        let json = #"{"name": "Logic Pro", "bundleID": "com.apple.logic10"}"#.data(using: .utf8)!

        XCTAssertNil(try JSONDecoder().decode(DAWEntry.self, from: json).icon)
    }
}
