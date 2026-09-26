import XCTest
@testable import StudioSwitchCore

final class DiskUtilMountedDiskInspectorTests: XCTestCase {
    func test_wattage_matchesWhenSystemProfilerNameContainsDiskutilName() {
        let entries: [(name: String, power: String?)] = [("Netac MobileDataStar", "4.48 W (896 mA)")]

        XCTAssertEqual(DiskUtilMountedDiskInspector.wattage(forMediaName: "MobileDataStar", in: entries), "4.48 W (896 mA)")
    }

    func test_wattage_matchesWhenDiskutilNameContainsSystemProfilerName() {
        let entries: [(name: String, power: String?)] = [("Crucial", "2.5 W (500 mA)")]

        XCTAssertEqual(DiskUtilMountedDiskInspector.wattage(forMediaName: "Crucial X9 4TO", in: entries), "2.5 W (500 mA)")
    }

    func test_wattage_nilWhenNoEntryCorrelates() {
        let entries: [(name: String, power: String?)] = [("Unrelated Device", "1 W")]

        XCTAssertNil(DiskUtilMountedDiskInspector.wattage(forMediaName: "MobileDataStar", in: entries))
    }

    func test_wattage_nilWhenMatchingEntryReportsNoPower() {
        let entries: [(name: String, power: String?)] = [("Netac MobileDataStar", nil)]

        XCTAssertNil(DiskUtilMountedDiskInspector.wattage(forMediaName: "MobileDataStar", in: entries))
    }
}
