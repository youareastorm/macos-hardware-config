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
              "uadConsoleSession": "~/Documents/Universal Audio/Sessions/home guit vox.uadmix",
              "useIACDriver": false,
              "daws": [
                { "name": "Logic Pro", "bundleID": "com.apple.logic10", "templatePath": null }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ProfilesFile.self, from: json)

        XCTAssertEqual(decoded.profiles.count, 1)
        XCTAssertEqual(decoded.profiles[0].name, "Home")
        XCTAssertEqual(decoded.profiles[0].deviceNameMatch, "Apollo Solo")
        XCTAssertEqual(decoded.profiles[0].daws[0].bundleID, "com.apple.logic10")
        XCTAssertNil(decoded.profiles[0].daws[0].templatePath)
    }
}
