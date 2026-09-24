# StudioSwitch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build StudioSwitch, a macOS menu-bar app that detects which Universal Audio Apollo interface is connected, switches the system's default audio device, optionally enables the IAC MIDI driver, loads the matching UAD Console session, and launches a chosen DAW (with an optional project template).

**Architecture:** Core logic lives in a testable Swift Package library (`StudioSwitchCore`) built from small protocol-backed components (device detection, audio/MIDI configuration, app opening, DAW launching), so everything except the real CoreAudio/CoreMIDI calls and the SwiftUI shell has unit tests. A thin executable target (`StudioSwitchApp`) wraps this in a SwiftUI `MenuBarExtra`, and a build script packages the release binary into a real `.app` bundle (LSUIElement, ad-hoc signed) for double-click / Login Item use. This delivers the spec's "menu-bar app, non-sandboxed" requirement without hand-authoring an `.xcodeproj`, while keeping every non-UI component testable from the command line via `swift test`.

**Tech Stack:** Swift 5.9+, Swift Package Manager, SwiftUI (`MenuBarExtra`, macOS 13+), CoreAudio, CoreMIDI, AppKit (`NSWorkspace`), XCTest.

**Spec:** docs/superpowers/specs/2026-09-25-studioswitch-design.md

## Global Constraints

- macOS 13 (Ventura) minimum deployment target (required by `MenuBarExtra`).
- The app is NOT sandboxed.
- Config file lives at `~/Library/Application Support/StudioSwitch/profiles.json`, hand-editable by Simon.
- Never write to any DAW's own preference files (Ableton `Preferences.cfg`, Logic/Pro Tools/Cubase plists, Bitwig plist) — explicitly out of scope per spec.
- No programmatic editing of the Audio MIDI Setup "MIDI Studio" window — only the IAC Driver's online/offline state via CoreMIDI's public `kMIDIPropertyOffline`.
- UAD Console app path is fixed: `/Applications/Universal Audio/UAD Console.app`.
- `deviceNameMatch` values must be matched case-insensitively but as an **exact** device name, never a loose substring (prevents "Apollo" matching "Apollo Solo").

## Review Focus

- Two profiles with similar device names (e.g. Home's "Apollo Solo" vs Studio's "Apollo x8p") must never cross-match — clicking "Studio" while only the Home unit is plugged in must report "not detected", not silently activate the wrong profile.
- A hand-edited `profiles.json` that is malformed JSON must produce a clear, catchable error, not a crash.
- `uadConsoleSession` paths starting with `~` (as in the spec's own example) must be expanded to the real home directory before being checked or opened.
- A DAW entry with a missing/incorrect `bundleID` must not stop the whole activation — the interface-detection and UAD Console steps must still complete and be reported independently.
- A DAW entry whose `templatePath` file no longer exists must still launch the DAW itself (without the template), per the spec's error-handling rule, rather than failing the whole launch.

---

### Task 1: Package scaffold + Profile model

**Files:**
- Create: `Package.swift`
- Create: `Sources/StudioSwitchCore/Models/Profile.swift`
- Test: `Tests/StudioSwitchCoreTests/ProfileTests.swift`

**Interfaces:**
- Produces: `DAWEntry(name: String, bundleID: String, templatePath: String?)`, `Profile(name: String, deviceNameMatch: String, uadConsoleSession: String, useIACDriver: Bool, daws: [DAWEntry])`, `ProfilesFile(profiles: [Profile])` — all `Codable, Equatable`.

- [ ] **Step 1: Scaffold the package manifest**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StudioSwitch",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "StudioSwitchCore", targets: ["StudioSwitchCore"]),
        .executable(name: "StudioSwitchApp", targets: ["StudioSwitchApp"])
    ],
    targets: [
        .target(name: "StudioSwitchCore"),
        .executableTarget(name: "StudioSwitchApp", dependencies: ["StudioSwitchCore"]),
        .testTarget(name: "StudioSwitchCoreTests", dependencies: ["StudioSwitchCore"])
    ]
)
```

Save as `Package.swift` at the repo root.

- [ ] **Step 2: Write the failing test**

```swift
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
```

Save as `Tests/StudioSwitchCoreTests/ProfileTests.swift`. Also create an empty `Sources/StudioSwitchApp/main.swift` containing just `print("StudioSwitch")` so the executable target builds during this step.

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter ProfileTests`
Expected: FAIL — build error, `cannot find type 'ProfilesFile' in scope` (or similar; `StudioSwitchCore` has no source files yet).

- [ ] **Step 4: Implement the model**

```swift
import Foundation

public struct DAWEntry: Codable, Equatable {
    public let name: String
    public let bundleID: String
    public let templatePath: String?

    public init(name: String, bundleID: String, templatePath: String?) {
        self.name = name
        self.bundleID = bundleID
        self.templatePath = templatePath
    }
}

public struct Profile: Codable, Equatable {
    public let name: String
    public let deviceNameMatch: String
    public let uadConsoleSession: String
    public let useIACDriver: Bool
    public let daws: [DAWEntry]

    public init(name: String, deviceNameMatch: String, uadConsoleSession: String, useIACDriver: Bool, daws: [DAWEntry]) {
        self.name = name
        self.deviceNameMatch = deviceNameMatch
        self.uadConsoleSession = uadConsoleSession
        self.useIACDriver = useIACDriver
        self.daws = daws
    }
}

public struct ProfilesFile: Codable, Equatable {
    public let profiles: [Profile]

    public init(profiles: [Profile]) {
        self.profiles = profiles
    }
}
```

Save as `Sources/StudioSwitchCore/Models/Profile.swift`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter ProfileTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/StudioSwitchCore/Models/Profile.swift Sources/StudioSwitchApp/main.swift Tests/StudioSwitchCoreTests/ProfileTests.swift
git commit -m "feat: scaffold StudioSwitch package and Profile model"
```

---

### Task 2: ProfileStore (load / seed default config)

**Files:**
- Create: `Sources/StudioSwitchCore/Models/ProfileStore.swift`
- Test: `Tests/StudioSwitchCoreTests/ProfileStoreTests.swift`

**Interfaces:**
- Consumes: `Profile`, `DAWEntry`, `ProfilesFile` from Task 1.
- Produces: `ProfileStoreError.decodingFailed(String)`; `ProfileStore(configURL: URL = ProfileStore.defaultConfigURL, fileManager: FileManager = .default)`; `ProfileStore.defaultConfigURL: URL`; `ProfileStore.defaultProfilesFile: ProfilesFile`; `store.loadProfiles() throws -> [Profile]`; `store.ensureDefaultConfigExists() throws`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

Save as `Tests/StudioSwitchCoreTests/ProfileStoreTests.swift`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ProfileStoreTests`
Expected: FAIL — `cannot find 'ProfileStore' in scope`.

- [ ] **Step 3: Implement ProfileStore**

```swift
import Foundation

public enum ProfileStoreError: Error, Equatable {
    case decodingFailed(String)
}

public final class ProfileStore {
    public static var defaultConfigURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/StudioSwitch/profiles.json")
    }

    public static let defaultProfilesFile = ProfilesFile(profiles: [
        Profile(
            name: "Home",
            deviceNameMatch: "Apollo Solo",
            uadConsoleSession: "~/Documents/Universal Audio/Sessions/home guit vox.uadmix",
            useIACDriver: false,
            daws: [
                DAWEntry(name: "Logic Pro", bundleID: "com.apple.logic10", templatePath: nil),
                DAWEntry(name: "Ableton Live 12 Suite", bundleID: "com.ableton.live", templatePath: nil)
            ]
        ),
        Profile(
            name: "Studio",
            deviceNameMatch: "Apollo",
            uadConsoleSession: "~/Documents/Universal Audio/Sessions/octo.uadmix",
            useIACDriver: false,
            daws: [
                DAWEntry(name: "Pro Tools", bundleID: "com.avid.ProTools", templatePath: nil),
                DAWEntry(name: "Cubase 15", bundleID: "com.steinberg.cubase15", templatePath: nil)
            ]
        )
    ])

    private let configURL: URL
    private let fileManager: FileManager

    public init(configURL: URL = ProfileStore.defaultConfigURL, fileManager: FileManager = .default) {
        self.configURL = configURL
        self.fileManager = fileManager
    }

    public func loadProfiles() throws -> [Profile] {
        if !fileManager.fileExists(atPath: configURL.path) {
            try ensureDefaultConfigExists()
        }
        let data = try Data(contentsOf: configURL)
        do {
            return try JSONDecoder().decode(ProfilesFile.self, from: data).profiles
        } catch {
            throw ProfileStoreError.decodingFailed("\(error)")
        }
    }

    public func ensureDefaultConfigExists() throws {
        guard !fileManager.fileExists(atPath: configURL.path) else { return }
        try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ProfileStore.defaultProfilesFile)
        try data.write(to: configURL)
    }
}
```

Save as `Sources/StudioSwitchCore/Models/ProfileStore.swift`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ProfileStoreTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/StudioSwitchCore/Models/ProfileStore.swift Tests/StudioSwitchCoreTests/ProfileStoreTests.swift
git commit -m "feat: add ProfileStore with default config seeding"
```

---

### Task 3: AudioInterfaceDetector (device detection)

**Files:**
- Create: `Sources/StudioSwitchCore/Audio/AudioDeviceProviding.swift`
- Create: `Sources/StudioSwitchCore/Audio/CoreAudioDeviceProvider.swift`
- Create: `Sources/StudioSwitchCore/Audio/AudioInterfaceDetector.swift`
- Test: `Tests/StudioSwitchCoreTests/AudioInterfaceDetectorTests.swift`

**Interfaces:**
- Consumes: `Profile` from Task 1.
- Produces: `protocol AudioDeviceProviding { connectedDeviceNames() -> [String]; deviceID(named: String) -> AudioDeviceID?; setDefaultDevice(_:selector:) throws }`; `CoreAudioDeviceProvider: AudioDeviceProviding`; `protocol DeviceDetecting { matchingDeviceName(for: Profile) -> String? }`; `AudioInterfaceDetector(provider: AudioDeviceProviding = CoreAudioDeviceProvider()): DeviceDetecting`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import CoreAudio
@testable import StudioSwitchCore

private final class MockAudioDeviceProvider: AudioDeviceProviding {
    var names: [String]
    init(names: [String]) { self.names = names }
    func connectedDeviceNames() -> [String] { names }
    func deviceID(named exactName: String) -> AudioDeviceID? { nil }
    func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws {}
}

final class AudioInterfaceDetectorTests: XCTestCase {
    func test_matchesExactCaseInsensitiveDeviceName() {
        let detector = AudioInterfaceDetector(provider: MockAudioDeviceProvider(names: ["MacBook Pro Speakers", "apollo solo"]))
        let profile = Profile(name: "Home", deviceNameMatch: "Apollo Solo", uadConsoleSession: "s", useIACDriver: false, daws: [])

        XCTAssertEqual(detector.matchingDeviceName(for: profile), "apollo solo")
    }

    func test_doesNotCrossMatchSimilarProfileNames() {
        let detector = AudioInterfaceDetector(provider: MockAudioDeviceProvider(names: ["Apollo Solo"]))
        let studioProfile = Profile(name: "Studio", deviceNameMatch: "Apollo x8p", uadConsoleSession: "s", useIACDriver: false, daws: [])

        XCTAssertNil(detector.matchingDeviceName(for: studioProfile))
    }

    func test_returnsNilWhenNoDevicesConnected() {
        let detector = AudioInterfaceDetector(provider: MockAudioDeviceProvider(names: []))
        let profile = Profile(name: "Home", deviceNameMatch: "Apollo Solo", uadConsoleSession: "s", useIACDriver: false, daws: [])

        XCTAssertNil(detector.matchingDeviceName(for: profile))
    }
}
```

Save as `Tests/StudioSwitchCoreTests/AudioInterfaceDetectorTests.swift`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AudioInterfaceDetectorTests`
Expected: FAIL — `cannot find type 'AudioDeviceProviding' in scope`.

- [ ] **Step 3: Implement the provider protocol**

```swift
import CoreAudio

public protocol AudioDeviceProviding {
    func connectedDeviceNames() -> [String]
    func deviceID(named exactName: String) -> AudioDeviceID?
    func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws
}
```

Save as `Sources/StudioSwitchCore/Audio/AudioDeviceProviding.swift`.

- [ ] **Step 4: Implement the real CoreAudio-backed provider**

```swift
import CoreAudio
import Foundation

public enum CoreAudioError: Error, Equatable {
    case propertyWriteFailed(OSStatus)
}

public final class CoreAudioDeviceProvider: AudioDeviceProviding {
    public init() {}

    public func connectedDeviceNames() -> [String] {
        deviceIDsAndNames().map(\.name)
    }

    public func deviceID(named exactName: String) -> AudioDeviceID? {
        deviceIDsAndNames().first { $0.name.caseInsensitiveCompare(exactName) == .orderedSame }?.id
    }

    public func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )
        guard status == noErr else { throw CoreAudioError.propertyWriteFailed(status) }
    }

    private func deviceIDsAndNames() -> [(id: AudioDeviceID, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }
        return deviceIDs.compactMap { id in
            guard let name = deviceName(for: id) else { return nil }
            return (id, name)
        }
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? (name as String) : nil
    }
}
```

Save as `Sources/StudioSwitchCore/Audio/CoreAudioDeviceProvider.swift`. This class has no dedicated unit tests — it talks to real hardware, per the spec's note that CoreAudio calls are verified manually.

- [ ] **Step 5: Implement AudioInterfaceDetector**

```swift
public protocol DeviceDetecting {
    func matchingDeviceName(for profile: Profile) -> String?
}

public final class AudioInterfaceDetector: DeviceDetecting {
    private let provider: AudioDeviceProviding

    public init(provider: AudioDeviceProviding = CoreAudioDeviceProvider()) {
        self.provider = provider
    }

    public func matchingDeviceName(for profile: Profile) -> String? {
        provider.connectedDeviceNames().first {
            $0.caseInsensitiveCompare(profile.deviceNameMatch) == .orderedSame
        }
    }
}
```

Save as `Sources/StudioSwitchCore/Audio/AudioInterfaceDetector.swift`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter AudioInterfaceDetectorTests`
Expected: PASS (3 tests)

- [ ] **Step 7: Commit**

```bash
git add Sources/StudioSwitchCore/Audio/AudioDeviceProviding.swift Sources/StudioSwitchCore/Audio/CoreAudioDeviceProvider.swift Sources/StudioSwitchCore/Audio/AudioInterfaceDetector.swift Tests/StudioSwitchCoreTests/AudioInterfaceDetectorTests.swift
git commit -m "feat: add CoreAudio-backed interface detection"
```

---

### Task 4: AudioMIDIConfigurator (default device + IAC driver)

**Files:**
- Create: `Sources/StudioSwitchCore/Audio/MIDIDeviceProviding.swift`
- Create: `Sources/StudioSwitchCore/Audio/CoreMIDIDeviceProvider.swift`
- Create: `Sources/StudioSwitchCore/Audio/AudioMIDIConfigurator.swift`
- Test: `Tests/StudioSwitchCoreTests/AudioMIDIConfiguratorTests.swift`

**Interfaces:**
- Consumes: `AudioDeviceProviding` from Task 3.
- Produces: `protocol MIDIDeviceProviding { iacDriverIsPresent() -> Bool; enableIACDriver() throws }`; `CoreMIDIDeviceProvider: MIDIDeviceProviding`; `protocol AudioMIDIConfiguring { setDefaultDevice(named: String) throws; enableIACDriverIfPresent() throws }`; `AudioMIDIConfiguratorError.deviceNotFound(String)`; `AudioMIDIConfigurator(deviceProvider:midiProvider:): AudioMIDIConfiguring`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import CoreAudio
@testable import StudioSwitchCore

private final class MockAudioDeviceProvider: AudioDeviceProviding {
    var idsByName: [String: AudioDeviceID] = [:]
    private(set) var setDefaultCalls: [(AudioDeviceID, AudioObjectPropertySelector)] = []
    func connectedDeviceNames() -> [String] { Array(idsByName.keys) }
    func deviceID(named exactName: String) -> AudioDeviceID? { idsByName[exactName] }
    func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws {
        setDefaultCalls.append((deviceID, selector))
    }
}

private final class MockMIDIDeviceProvider: MIDIDeviceProviding {
    var present: Bool
    private(set) var enableCallCount = 0
    init(present: Bool) { self.present = present }
    func iacDriverIsPresent() -> Bool { present }
    func enableIACDriver() throws { enableCallCount += 1 }
}

final class AudioMIDIConfiguratorTests: XCTestCase {
    func test_setDefaultDevice_setsInputOutputAndSystemOutput() throws {
        let deviceProvider = MockAudioDeviceProvider()
        deviceProvider.idsByName["Apollo Solo"] = 42
        let configurator = AudioMIDIConfigurator(deviceProvider: deviceProvider, midiProvider: MockMIDIDeviceProvider(present: false))

        try configurator.setDefaultDevice(named: "Apollo Solo")

        XCTAssertEqual(deviceProvider.setDefaultCalls.map(\.0), [42, 42, 42])
        XCTAssertEqual(deviceProvider.setDefaultCalls.map(\.1), [
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice
        ])
    }

    func test_setDefaultDevice_throwsWhenDeviceNotFound() {
        let configurator = AudioMIDIConfigurator(deviceProvider: MockAudioDeviceProvider(), midiProvider: MockMIDIDeviceProvider(present: false))

        XCTAssertThrowsError(try configurator.setDefaultDevice(named: "Missing")) { error in
            XCTAssertEqual(error as? AudioMIDIConfiguratorError, .deviceNotFound("Missing"))
        }
    }

    func test_enableIACDriverIfPresent_enablesWhenPresent() throws {
        let midiProvider = MockMIDIDeviceProvider(present: true)
        let configurator = AudioMIDIConfigurator(deviceProvider: MockAudioDeviceProvider(), midiProvider: midiProvider)

        try configurator.enableIACDriverIfPresent()

        XCTAssertEqual(midiProvider.enableCallCount, 1)
    }

    func test_enableIACDriverIfPresent_doesNothingWhenAbsent() throws {
        let midiProvider = MockMIDIDeviceProvider(present: false)
        let configurator = AudioMIDIConfigurator(deviceProvider: MockAudioDeviceProvider(), midiProvider: midiProvider)

        try configurator.enableIACDriverIfPresent()

        XCTAssertEqual(midiProvider.enableCallCount, 0)
    }
}
```

Save as `Tests/StudioSwitchCoreTests/AudioMIDIConfiguratorTests.swift`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AudioMIDIConfiguratorTests`
Expected: FAIL — `cannot find 'AudioMIDIConfigurator' in scope`.

- [ ] **Step 3: Implement MIDIDeviceProviding + CoreMIDIDeviceProvider**

```swift
public protocol MIDIDeviceProviding {
    func iacDriverIsPresent() -> Bool
    func enableIACDriver() throws
}
```

Save as `Sources/StudioSwitchCore/Audio/MIDIDeviceProviding.swift`.

```swift
import CoreMIDI

public enum CoreMIDIError: Error, Equatable {
    case iacDriverNotFound
    case propertyWriteFailed(OSStatus)
}

public final class CoreMIDIDeviceProvider: MIDIDeviceProviding {
    public init() {}

    public func iacDriverIsPresent() -> Bool {
        iacDriverDevice() != nil
    }

    public func enableIACDriver() throws {
        guard let device = iacDriverDevice() else { throw CoreMIDIError.iacDriverNotFound }
        let status = MIDIObjectSetIntegerProperty(device, kMIDIPropertyOffline, 0)
        guard status == noErr else { throw CoreMIDIError.propertyWriteFailed(status) }
    }

    private func iacDriverDevice() -> MIDIDeviceRef? {
        for index in 0..<MIDIGetNumberOfDevices() {
            let device = MIDIGetDevice(index)
            var nameRef: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(device, kMIDIPropertyName, &nameRef) == noErr,
                  let name = nameRef?.takeRetainedValue() as String?,
                  name == "IAC Driver" else { continue }
            return device
        }
        return nil
    }
}
```

Save as `Sources/StudioSwitchCore/Audio/CoreMIDIDeviceProvider.swift`. No dedicated unit tests — talks to real MIDI hardware/drivers, verified manually.

- [ ] **Step 4: Implement AudioMIDIConfigurator**

```swift
import CoreAudio

public protocol AudioMIDIConfiguring {
    func setDefaultDevice(named deviceName: String) throws
    func enableIACDriverIfPresent() throws
}

public enum AudioMIDIConfiguratorError: Error, Equatable {
    case deviceNotFound(String)
}

public final class AudioMIDIConfigurator: AudioMIDIConfiguring {
    private let deviceProvider: AudioDeviceProviding
    private let midiProvider: MIDIDeviceProviding

    public init(deviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider(), midiProvider: MIDIDeviceProviding = CoreMIDIDeviceProvider()) {
        self.deviceProvider = deviceProvider
        self.midiProvider = midiProvider
    }

    public func setDefaultDevice(named deviceName: String) throws {
        guard let deviceID = deviceProvider.deviceID(named: deviceName) else {
            throw AudioMIDIConfiguratorError.deviceNotFound(deviceName)
        }
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
        try deviceProvider.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    public func enableIACDriverIfPresent() throws {
        guard midiProvider.iacDriverIsPresent() else { return }
        try midiProvider.enableIACDriver()
    }
}
```

Save as `Sources/StudioSwitchCore/Audio/AudioMIDIConfigurator.swift`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter AudioMIDIConfiguratorTests`
Expected: PASS (4 tests)

- [ ] **Step 6: Commit**

```bash
git add Sources/StudioSwitchCore/Audio/MIDIDeviceProviding.swift Sources/StudioSwitchCore/Audio/CoreMIDIDeviceProvider.swift Sources/StudioSwitchCore/Audio/AudioMIDIConfigurator.swift Tests/StudioSwitchCoreTests/AudioMIDIConfiguratorTests.swift
git commit -m "feat: add default device switching and IAC driver enabling"
```

---

### Task 5: App opening primitives + UADConsoleController

**Files:**
- Create: `Sources/StudioSwitchCore/System/AppOpening.swift`
- Create: `Sources/StudioSwitchCore/UAD/UADConsoleController.swift`
- Test: `Tests/StudioSwitchCoreTests/UADConsoleControllerTests.swift`

**Interfaces:**
- Produces: `protocol AppLocating { applicationURL(forBundleID: String) -> URL? }`; `protocol AppLaunching { launchApplication(at: URL) throws; open(fileURL: URL, withApplicationAt: URL) throws }`; `WorkspaceAppLocator: AppLocating`; `WorkspaceAppLauncher: AppLaunching`; `protocol UADSessionOpening { openSession(atPath: String) throws }`; `UADConsoleControllerError.sessionFileNotFound(String)`, `.consoleAppNotFound(String)`; `UADConsoleController(appLauncher:fileManager:consoleAppPath:): UADSessionOpening`; `UADConsoleController.defaultConsoleAppPath`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import StudioSwitchCore

private final class MockAppLauncher: AppLaunching {
    private(set) var openedFileURL: URL?
    private(set) var openedAppURL: URL?
    func launchApplication(at appURL: URL) throws {}
    func open(fileURL: URL, withApplicationAt appURL: URL) throws {
        openedFileURL = fileURL
        openedAppURL = appURL
    }
}

final class UADConsoleControllerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func test_openSession_opensExistingFileWithConsoleApp() throws {
        let sessionURL = tempDirectory.appendingPathComponent("session.uadmix")
        try Data().write(to: sessionURL)
        let consoleAppURL = tempDirectory.appendingPathComponent("UAD Console.app")
        try FileManager.default.createDirectory(at: consoleAppURL, withIntermediateDirectories: true)
        let launcher = MockAppLauncher()
        let controller = UADConsoleController(appLauncher: launcher, consoleAppPath: consoleAppURL.path)

        try controller.openSession(atPath: sessionURL.path)

        XCTAssertEqual(launcher.openedFileURL, sessionURL)
        XCTAssertEqual(launcher.openedAppURL, consoleAppURL)
    }

    func test_openSession_throwsWhenSessionFileMissing() {
        let controller = UADConsoleController(appLauncher: MockAppLauncher(), consoleAppPath: tempDirectory.path)

        XCTAssertThrowsError(try controller.openSession(atPath: tempDirectory.appendingPathComponent("missing.uadmix").path)) { error in
            guard case UADConsoleControllerError.sessionFileNotFound = error else {
                return XCTFail("expected sessionFileNotFound, got \(error)")
            }
        }
    }

    func test_openSession_throwsWhenConsoleAppMissing() throws {
        let sessionURL = tempDirectory.appendingPathComponent("session.uadmix")
        try Data().write(to: sessionURL)
        let controller = UADConsoleController(appLauncher: MockAppLauncher(), consoleAppPath: tempDirectory.appendingPathComponent("NoConsole.app").path)

        XCTAssertThrowsError(try controller.openSession(atPath: sessionURL.path)) { error in
            guard case UADConsoleControllerError.consoleAppNotFound = error else {
                return XCTFail("expected consoleAppNotFound, got \(error)")
            }
        }
    }

    func test_openSession_expandsTildeInPath() throws {
        let controller = UADConsoleController(appLauncher: MockAppLauncher(), consoleAppPath: tempDirectory.path)

        XCTAssertThrowsError(try controller.openSession(atPath: "~/StudioSwitchTests-does-not-exist.uadmix")) { error in
            guard case UADConsoleControllerError.sessionFileNotFound(let path) = error else {
                return XCTFail("expected sessionFileNotFound, got \(error)")
            }
            XCTAssertFalse(path.hasPrefix("~"))
        }
    }
}
```

Save as `Tests/StudioSwitchCoreTests/UADConsoleControllerTests.swift`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter UADConsoleControllerTests`
Expected: FAIL — `cannot find 'UADConsoleController' in scope`.

- [ ] **Step 3: Implement the app-opening primitives**

```swift
import AppKit
import Foundation

public protocol AppLocating {
    func applicationURL(forBundleID bundleID: String) -> URL?
}

public protocol AppLaunching {
    func launchApplication(at appURL: URL) throws
    func open(fileURL: URL, withApplicationAt appURL: URL) throws
}

public final class WorkspaceAppLocator: AppLocating {
    public init() {}

    public func applicationURL(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

public final class WorkspaceAppLauncher: AppLaunching {
    public init() {}

    public func launchApplication(at appURL: URL) throws {
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    public func open(fileURL: URL, withApplicationAt appURL: URL) throws {
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
```

Save as `Sources/StudioSwitchCore/System/AppOpening.swift`.

- [ ] **Step 4: Implement UADConsoleController**

```swift
import Foundation

public protocol UADSessionOpening {
    func openSession(atPath path: String) throws
}

public enum UADConsoleControllerError: Error, Equatable {
    case sessionFileNotFound(String)
    case consoleAppNotFound(String)
}

public final class UADConsoleController: UADSessionOpening {
    public static let defaultConsoleAppPath = "/Applications/Universal Audio/UAD Console.app"

    private let appLauncher: AppLaunching
    private let fileManager: FileManager
    private let consoleAppPath: String

    public init(appLauncher: AppLaunching = WorkspaceAppLauncher(), fileManager: FileManager = .default, consoleAppPath: String = UADConsoleController.defaultConsoleAppPath) {
        self.appLauncher = appLauncher
        self.fileManager = fileManager
        self.consoleAppPath = consoleAppPath
    }

    public func openSession(atPath path: String) throws {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: expandedPath) else {
            throw UADConsoleControllerError.sessionFileNotFound(expandedPath)
        }
        guard fileManager.fileExists(atPath: consoleAppPath) else {
            throw UADConsoleControllerError.consoleAppNotFound(consoleAppPath)
        }
        try appLauncher.open(fileURL: URL(fileURLWithPath: expandedPath), withApplicationAt: URL(fileURLWithPath: consoleAppPath))
    }
}
```

Save as `Sources/StudioSwitchCore/UAD/UADConsoleController.swift`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter UADConsoleControllerTests`
Expected: PASS (4 tests)

- [ ] **Step 6: Commit**

```bash
git add Sources/StudioSwitchCore/System/AppOpening.swift Sources/StudioSwitchCore/UAD/UADConsoleController.swift Tests/StudioSwitchCoreTests/UADConsoleControllerTests.swift
git commit -m "feat: add UAD Console session opening"
```

---

### Task 6: DAWLauncher

**Files:**
- Create: `Sources/StudioSwitchCore/DAW/DAWLauncher.swift`
- Test: `Tests/StudioSwitchCoreTests/DAWLauncherTests.swift`

**Interfaces:**
- Consumes: `AppLocating`, `AppLaunching` from Task 5; `DAWEntry` from Task 1.
- Produces: `DAWLauncherError.applicationNotFound(String)`; `DAWLauncher(appLocator:appLauncher:fileManager:)`; `launcher.launch(_ daw: DAWEntry) throws`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import StudioSwitchCore

private final class MockAppLocator: AppLocating {
    var urlsByBundleID: [String: URL] = [:]
    func applicationURL(forBundleID bundleID: String) -> URL? { urlsByBundleID[bundleID] }
}

private final class MockAppLauncher: AppLaunching {
    private(set) var launchedAppURL: URL?
    private(set) var openedFileURL: URL?
    private(set) var openedAppURL: URL?
    func launchApplication(at appURL: URL) throws { launchedAppURL = appURL }
    func open(fileURL: URL, withApplicationAt appURL: URL) throws {
        openedFileURL = fileURL
        openedAppURL = appURL
    }
}

final class DAWLauncherTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func test_launch_throwsWhenApplicationNotFound() {
        let launcher = DAWLauncher(appLocator: MockAppLocator(), appLauncher: MockAppLauncher())
        let daw = DAWEntry(name: "Logic Pro", bundleID: "com.apple.logic10", templatePath: nil)

        XCTAssertThrowsError(try launcher.launch(daw)) { error in
            XCTAssertEqual(error as? DAWLauncherError, .applicationNotFound("com.apple.logic10"))
        }
    }

    func test_launch_launchesAppDirectlyWhenNoTemplate() throws {
        let appURL = tempDirectory.appendingPathComponent("Logic Pro.app")
        let locator = MockAppLocator()
        locator.urlsByBundleID["com.apple.logic10"] = appURL
        let appLauncher = MockAppLauncher()
        let launcher = DAWLauncher(appLocator: locator, appLauncher: appLauncher)

        try launcher.launch(DAWEntry(name: "Logic Pro", bundleID: "com.apple.logic10", templatePath: nil))

        XCTAssertEqual(appLauncher.launchedAppURL, appURL)
        XCTAssertNil(appLauncher.openedFileURL)
    }

    func test_launch_opensTemplateWhenPresent() throws {
        let appURL = tempDirectory.appendingPathComponent("Logic Pro.app")
        let templateURL = tempDirectory.appendingPathComponent("template.logicx")
        try Data().write(to: templateURL)
        let locator = MockAppLocator()
        locator.urlsByBundleID["com.apple.logic10"] = appURL
        let appLauncher = MockAppLauncher()
        let launcher = DAWLauncher(appLocator: locator, appLauncher: appLauncher)

        try launcher.launch(DAWEntry(name: "Logic Pro", bundleID: "com.apple.logic10", templatePath: templateURL.path))

        XCTAssertEqual(appLauncher.openedFileURL, templateURL)
        XCTAssertEqual(appLauncher.openedAppURL, appURL)
        XCTAssertNil(appLauncher.launchedAppURL)
    }

    func test_launch_fallsBackToPlainLaunchWhenTemplateMissing() throws {
        let appURL = tempDirectory.appendingPathComponent("Logic Pro.app")
        let locator = MockAppLocator()
        locator.urlsByBundleID["com.apple.logic10"] = appURL
        let appLauncher = MockAppLauncher()
        let launcher = DAWLauncher(appLocator: locator, appLauncher: appLauncher)

        try launcher.launch(DAWEntry(name: "Logic Pro", bundleID: "com.apple.logic10", templatePath: tempDirectory.appendingPathComponent("missing.logicx").path))

        XCTAssertEqual(appLauncher.launchedAppURL, appURL)
        XCTAssertNil(appLauncher.openedFileURL)
    }
}
```

Save as `Tests/StudioSwitchCoreTests/DAWLauncherTests.swift`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DAWLauncherTests`
Expected: FAIL — `cannot find 'DAWLauncher' in scope`.

- [ ] **Step 3: Implement DAWLauncher**

```swift
import Foundation

public enum DAWLauncherError: Error, Equatable {
    case applicationNotFound(String)
}

public final class DAWLauncher {
    private let appLocator: AppLocating
    private let appLauncher: AppLaunching
    private let fileManager: FileManager

    public init(appLocator: AppLocating = WorkspaceAppLocator(), appLauncher: AppLaunching = WorkspaceAppLauncher(), fileManager: FileManager = .default) {
        self.appLocator = appLocator
        self.appLauncher = appLauncher
        self.fileManager = fileManager
    }

    public func launch(_ daw: DAWEntry) throws {
        guard let appURL = appLocator.applicationURL(forBundleID: daw.bundleID) else {
            throw DAWLauncherError.applicationNotFound(daw.bundleID)
        }
        if let templatePath = daw.templatePath {
            let expandedPath = (templatePath as NSString).expandingTildeInPath
            if fileManager.fileExists(atPath: expandedPath) {
                try appLauncher.open(fileURL: URL(fileURLWithPath: expandedPath), withApplicationAt: appURL)
                return
            }
        }
        try appLauncher.launchApplication(at: appURL)
    }
}
```

Save as `Sources/StudioSwitchCore/DAW/DAWLauncher.swift`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DAWLauncherTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/StudioSwitchCore/DAW/DAWLauncher.swift Tests/StudioSwitchCoreTests/DAWLauncherTests.swift
git commit -m "feat: add DAW launcher with template fallback"
```

---

### Task 7: ProfileActivationController (orchestration)

**Files:**
- Create: `Sources/StudioSwitchCore/Activation/ProfileActivationController.swift`
- Test: `Tests/StudioSwitchCoreTests/ProfileActivationControllerTests.swift`

**Interfaces:**
- Consumes: `DeviceDetecting` (Task 3), `AudioMIDIConfiguring` (Task 4), `UADSessionOpening` (Task 5), `Profile` (Task 1).
- Produces: `ProfileActivationResult(profile:deviceDetected:deviceConfigError:uadConsoleError:)`; `ProfileActivationController(detector:configurator:uadConsole:)`; `controller.activate(_ profile: Profile) -> ProfileActivationResult`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import StudioSwitchCore

private final class MockDetector: DeviceDetecting {
    var matchedName: String?
    func matchingDeviceName(for profile: Profile) -> String? { matchedName }
}

private final class MockConfigurator: AudioMIDIConfiguring {
    var setDefaultDeviceError: Error?
    var enableIACDriverError: Error?
    private(set) var setDefaultDeviceCallCount = 0
    private(set) var enableIACDriverCallCount = 0

    func setDefaultDevice(named deviceName: String) throws {
        setDefaultDeviceCallCount += 1
        if let error = setDefaultDeviceError { throw error }
    }

    func enableIACDriverIfPresent() throws {
        enableIACDriverCallCount += 1
        if let error = enableIACDriverError { throw error }
    }
}

private final class MockUADConsole: UADSessionOpening {
    var openSessionError: Error?
    private(set) var openSessionCallCount = 0

    func openSession(atPath path: String) throws {
        openSessionCallCount += 1
        if let error = openSessionError { throw error }
    }
}

private enum TestError: Error { case boom }

final class ProfileActivationControllerTests: XCTestCase {
    private let profile = Profile(name: "Home", deviceNameMatch: "Apollo Solo", uadConsoleSession: "s", useIACDriver: false, daws: [])

    func test_activate_shortCircuitsWhenDeviceNotDetected() {
        let configurator = MockConfigurator()
        let uadConsole = MockUADConsole()
        let controller = ProfileActivationController(detector: MockDetector(), configurator: configurator, uadConsole: uadConsole)

        let result = controller.activate(profile)

        XCTAssertFalse(result.deviceDetected)
        XCTAssertEqual(configurator.setDefaultDeviceCallCount, 0)
        XCTAssertEqual(uadConsole.openSessionCallCount, 0)
    }

    func test_activate_configuresAudioAndOpensSessionWhenDeviceDetected() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let uadConsole = MockUADConsole()
        let controller = ProfileActivationController(detector: detector, configurator: configurator, uadConsole: uadConsole)

        let result = controller.activate(profile)

        XCTAssertTrue(result.deviceDetected)
        XCTAssertNil(result.deviceConfigError)
        XCTAssertNil(result.uadConsoleError)
        XCTAssertEqual(configurator.setDefaultDeviceCallCount, 1)
        XCTAssertEqual(uadConsole.openSessionCallCount, 1)
    }

    func test_activate_stillOpensSessionWhenDeviceConfigFails() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        configurator.setDefaultDeviceError = TestError.boom
        let uadConsole = MockUADConsole()
        let controller = ProfileActivationController(detector: detector, configurator: configurator, uadConsole: uadConsole)

        let result = controller.activate(profile)

        XCTAssertNotNil(result.deviceConfigError)
        XCTAssertEqual(uadConsole.openSessionCallCount, 1)
        XCTAssertNil(result.uadConsoleError)
    }

    func test_activate_reportsUADConsoleErrorWithoutFailingActivation() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let uadConsole = MockUADConsole()
        uadConsole.openSessionError = TestError.boom
        let controller = ProfileActivationController(detector: detector, configurator: MockConfigurator(), uadConsole: uadConsole)

        let result = controller.activate(profile)

        XCTAssertTrue(result.deviceDetected)
        XCTAssertNil(result.deviceConfigError)
        XCTAssertNotNil(result.uadConsoleError)
    }

    func test_activate_enablesIACDriverOnlyWhenProfileRequestsIt() {
        let detector = MockDetector()
        detector.matchedName = "Apollo Solo"
        let configurator = MockConfigurator()
        let profileWithIAC = Profile(name: "Home", deviceNameMatch: "Apollo Solo", uadConsoleSession: "s", useIACDriver: true, daws: [])
        let controller = ProfileActivationController(detector: detector, configurator: configurator, uadConsole: MockUADConsole())

        _ = controller.activate(profileWithIAC)

        XCTAssertEqual(configurator.enableIACDriverCallCount, 1)
    }
}
```

Save as `Tests/StudioSwitchCoreTests/ProfileActivationControllerTests.swift`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ProfileActivationControllerTests`
Expected: FAIL — `cannot find 'ProfileActivationController' in scope`.

- [ ] **Step 3: Implement ProfileActivationController**

```swift
public struct ProfileActivationResult: Equatable {
    public let profile: Profile
    public let deviceDetected: Bool
    public let deviceConfigError: String?
    public let uadConsoleError: String?
}

public final class ProfileActivationController {
    private let detector: DeviceDetecting
    private let configurator: AudioMIDIConfiguring
    private let uadConsole: UADSessionOpening

    public init(detector: DeviceDetecting, configurator: AudioMIDIConfiguring, uadConsole: UADSessionOpening) {
        self.detector = detector
        self.configurator = configurator
        self.uadConsole = uadConsole
    }

    public func activate(_ profile: Profile) -> ProfileActivationResult {
        guard let matchedName = detector.matchingDeviceName(for: profile) else {
            return ProfileActivationResult(profile: profile, deviceDetected: false, deviceConfigError: nil, uadConsoleError: nil)
        }

        var deviceConfigError: String?
        do {
            try configurator.setDefaultDevice(named: matchedName)
            if profile.useIACDriver {
                try configurator.enableIACDriverIfPresent()
            }
        } catch {
            deviceConfigError = "\(error)"
        }

        var uadConsoleError: String?
        do {
            try uadConsole.openSession(atPath: profile.uadConsoleSession)
        } catch {
            uadConsoleError = "\(error)"
        }

        return ProfileActivationResult(profile: profile, deviceDetected: true, deviceConfigError: deviceConfigError, uadConsoleError: uadConsoleError)
    }
}
```

Save as `Sources/StudioSwitchCore/Activation/ProfileActivationController.swift`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ProfileActivationControllerTests`
Expected: PASS (5 tests)

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: PASS — all tests across all tasks so far green.

- [ ] **Step 6: Commit**

```bash
git add Sources/StudioSwitchCore/Activation/ProfileActivationController.swift Tests/StudioSwitchCoreTests/ProfileActivationControllerTests.swift
git commit -m "feat: orchestrate profile activation across audio, MIDI and UAD Console"
```

---

### Task 8: SwiftUI menu bar app

**Files:**
- Modify: `Sources/StudioSwitchApp/main.swift` → delete (replaced by `@main` App below)
- Create: `Sources/StudioSwitchApp/StudioSwitchApp.swift`
- Create: `Sources/StudioSwitchApp/MenuBarView.swift`

**Interfaces:**
- Consumes: `ProfileStore`, `Profile`, `DAWEntry` (Task 1–2), `AudioInterfaceDetector` (Task 3), `AudioMIDIConfigurator` (Task 4), `UADConsoleController` (Task 5), `DAWLauncher` (Task 6), `ProfileActivationController`, `ProfileActivationResult` (Task 7).
- Produces: the running menu-bar UI. No automated tests — verified manually against real hardware (see Step 4).

- [ ] **Step 1: Remove the placeholder executable entry point**

Delete `Sources/StudioSwitchApp/main.swift` (it only printed a placeholder string in Task 1 so the executable target would build).

- [ ] **Step 2: Implement the App entry point**

```swift
import SwiftUI
import AppKit

@main
struct StudioSwitchApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("StudioSwitch", systemImage: "waveform") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

Save as `Sources/StudioSwitchApp/StudioSwitchApp.swift`. `setActivationPolicy(.accessory)` hides the Dock icon even without an Info.plist (the app bundle in Task 9 also sets `LSUIElement` as a second line of defense).

- [ ] **Step 3: Implement the menu bar view**

```swift
import SwiftUI
import AppKit
import StudioSwitchCore

struct MenuBarView: View {
    @State private var profiles: [Profile] = []
    @State private var activeProfile: Profile?
    @State private var lastResult: ProfileActivationResult?
    @State private var loadError: String?

    private let profileStore = ProfileStore()
    private let activationController = ProfileActivationController(
        detector: AudioInterfaceDetector(),
        configurator: AudioMIDIConfigurator(),
        uadConsole: UADConsoleController()
    )
    private let dawLauncher = DAWLauncher()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let loadError {
                Text("Erreur de config : \(loadError)").foregroundStyle(.red)
            }

            ForEach(profiles, id: \.name) { profile in
                Button(profile.name) {
                    lastResult = activationController.activate(profile)
                    activeProfile = lastResult?.deviceDetected == true ? profile : nil
                }
            }

            if let result = lastResult {
                Divider()
                statusText(for: result)
            }

            if let activeProfile {
                Divider()
                ForEach(activeProfile.daws, id: \.bundleID) { daw in
                    Button(daw.name) {
                        try? dawLauncher.launch(daw)
                    }
                }
            }

            Divider()
            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .onAppear(perform: loadProfiles)
    }

    private func loadProfiles() {
        do {
            profiles = try profileStore.loadProfiles()
        } catch {
            loadError = "\(error)"
        }
    }

    @ViewBuilder
    private func statusText(for result: ProfileActivationResult) -> some View {
        if !result.deviceDetected {
            Text("\(result.profile.deviceNameMatch) non détecté").foregroundStyle(.red)
        } else {
            if let error = result.deviceConfigError {
                Text("Erreur audio : \(error)").foregroundStyle(.orange)
            }
            if let error = result.uadConsoleError {
                Text("Erreur UAD Console : \(error)").foregroundStyle(.orange)
            }
            if result.deviceConfigError == nil && result.uadConsoleError == nil {
                Text("\(result.profile.name) activé").foregroundStyle(.green)
            }
        }
    }
}
```

Save as `Sources/StudioSwitchApp/MenuBarView.swift`.

- [ ] **Step 4: Build and manually verify**

Run: `swift build`
Expected: builds with no errors.

Manual check (on Simon's Mac, since this needs real hardware and cannot be unit tested):
1. `swift run StudioSwitchApp` — a waveform icon appears in the menu bar, no Dock icon.
2. With Apollo Solo connected, click "Home" — status line shows "Home activé", system default output switches to the Apollo Solo (check in System Settings → Sound), UAD Console opens the configured session.
3. Click a DAW button — the DAW launches.
4. Unplug the interface, click "Studio" — status line shows "Apollo non détecté" (or the exact `deviceNameMatch` configured), nothing else happens.

- [ ] **Step 5: Commit**

```bash
git add Sources/StudioSwitchApp/StudioSwitchApp.swift Sources/StudioSwitchApp/MenuBarView.swift
git rm Sources/StudioSwitchApp/main.swift
git commit -m "feat: add SwiftUI menu bar UI"
```

---

### Task 9: App bundle packaging + setup docs

**Files:**
- Create: `Scripts/build-app-bundle.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: the `StudioSwitchApp` executable product built by `Package.swift` (Task 1).
- Produces: a `StudioSwitch.app` bundle (build artifact, not committed) and updated setup instructions.

- [ ] **Step 1: Write the packaging script**

```bash
#!/bin/bash
set -euo pipefail

APP_NAME="StudioSwitch"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"

swift build -c release --product StudioSwitchApp

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
cp "${BUILD_DIR}/StudioSwitchApp" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.simonrenard.studioswitch</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "${APP_BUNDLE}"

echo "Built ${APP_BUNDLE}. Move it to /Applications and add it to Login Items to run it automatically."
```

Save as `Scripts/build-app-bundle.sh`.

- [ ] **Step 2: Make it executable and run it**

Run: `chmod +x Scripts/build-app-bundle.sh && ./Scripts/build-app-bundle.sh`
Expected: prints `Built StudioSwitch.app. ...` and creates `StudioSwitch.app/` at the repo root.

- [ ] **Step 3: Verify the bundle**

Run: `codesign --verify --deep --strict StudioSwitch.app && open StudioSwitch.app`
Expected: codesign verification succeeds silently; the app launches and its icon appears in the menu bar with no Dock icon.

- [ ] **Step 4: Update the README**

Add a "Setup" section to `README.md` covering:
- Prerequisites: macOS 13+, Xcode Command Line Tools, UAD Console + the target DAWs installed.
- Build & test: `swift build`, `swift test`.
- First run: `swift run StudioSwitchApp` to try it without packaging.
- Package as an app: `./Scripts/build-app-bundle.sh`, then move `StudioSwitch.app` to `/Applications` and add it to Login Items (System Settings → General → Login Items).
- Configuration: edit `~/Library/Application Support/StudioSwitch/profiles.json` (created automatically on first run) to adjust session paths, DAW bundle IDs and templates. To find the exact CoreAudio name of the Studio Apollo (the seeded config uses the placeholder `"Apollo"`), run `system_profiler SPAudioDataType | grep -B2 -A2 Apollo` and copy the exact device name into `deviceNameMatch`.

- [ ] **Step 5: Commit**

```bash
git add Scripts/build-app-bundle.sh README.md
git commit -m "feat: add app bundle packaging script and setup docs"
```

(`StudioSwitch.app`, produced by the script, is a build artifact — do not commit it; add `StudioSwitch.app/` and `.build/` to `.gitignore` if not already ignored.)

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-25-studioswitch-implementation.md`. Please review the plan. Which execution approach would you prefer?

- **Subagent-driven** — A fresh subagent implements each task and a fresh reviewer checks it before the next one starts, then a whole-branch review at the end. Most thorough; costs a fresh context per task and per review.
- **Native** — I implement every task myself in this session, then one fresh reviewer checks the whole branch at the end. Cheapest and fastest; no independent review until the end.

For this plan I recommend **Native**, because the 9 tasks are a linear, single-context build (each one's interfaces are fully pinned down here already) for a personal utility, not a shared/production system — the fresh-context overhead of a subagent-plus-reviewer per task costs more than it buys here, and a single end-of-branch review is enough to catch mistakes in code this fully specified.

Does the plan capture what you want, and which approach should we use?
