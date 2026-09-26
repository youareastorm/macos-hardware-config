# macos-hardware-config
macOS hardware detection and configuration utility

## StudioSwitch — Setup

StudioSwitch is a macOS menu-bar app that detects which Universal Audio Apollo interface is connected, switches the system's default audio device, loads the matching UAD Console session, and launches a chosen DAW.

### Prerequisites

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)
- UAD Console and the target DAWs installed (Logic Pro, Ableton Live, Pro Tools, Cubase, Bitwig Studio)

### Build & test

```bash
swift build
swift test
```

### First run (without packaging)

```bash
swift run StudioSwitchApp
```

### Package as an app

```bash
./Scripts/build-app-bundle.sh
```

This produces `StudioSwitch.app` at the repo root. Move it to `/Applications`, then add it to Login Items (System Settings → General → Login Items) to have it launch automatically.

### Configuration

StudioSwitch creates `~/Library/Application Support/StudioSwitch/profiles.json` on first run with two default profiles ("Home" and "Studio"). Edit this file to adjust session paths, DAW bundle IDs, and templates.

The seeded "Studio" profile uses the placeholder device name `"Apollo"` for `deviceNameMatch`. To find the exact CoreAudio name of your Studio Apollo, run:

```bash
system_profiler SPAudioDataType | grep -B2 -A2 Apollo
```

and copy the exact device name into `deviceNameMatch` — matching is exact (case-insensitive), not a substring match, so this must be precise.

Optional fields let a profile drive automatic setup and the health indicators (see below):

- `expectedSampleRate`: nominal sample rate in Hz the audio interface should be running at (e.g. `96000`). Omit or leave `null` to skip this check.
- `expectedExternalDiskNames`: volume names of external disks that should be mounted for this profile (e.g. `["Samples", "Backup"]`). Omit or leave `[]` to skip this check.
- `expectedOutputDeviceNames`: the device(s) the Mac's audio *output* should route to, separately from `audioDeviceName` (which is only the input/recording interface once this is set). One entry selects that device as the default output; two or more (e.g. `["Virtuel 1", "Virtuel 2"]`) make StudioSwitch create and select a combined Multi-Output Device the first time the profile is activated, and reuse it afterwards. Omit or leave `[]` to keep `audioDeviceName` as both input and output.

### Automatic setup on activation

Clicking a profile doesn't just detect state — it actively applies it:

- Sets the default input (and, without an `expectedOutputDeviceNames`, the output too) to `audioDeviceName`.
- When `expectedOutputDeviceNames` is set, creates/reuses the Multi-Output Device and sets it as the default output.
- Opens the profile's UAD Console session (`uadConsoleSession`). If a different session is already open, this currently just re-sends an "open" request to UAD Console — it does not quit/relaunch it, so if UAD Console ignores that request while another session is loaded, the "UAD Console" indicator below will still show red until you switch the session yourself.
- Enables the IAC Driver when `useIACDriver` is set.

Any step that fails is reported next to the profile buttons without blocking the others (e.g. a bad UAD Console path won't stop the audio device from being set).

### Health indicators

Clicking a profile in the menu bar runs a set of status checks and shows a colored dot per item: green (OK), yellow (warning), red (error). "Actualiser" re-runs them without reactivating the profile.

- **Interface audio** — is `audioDeviceName` online, at the expected sample rate, and set as the default input (and output, when the profile has no separate `expectedOutputDeviceNames`).
- **Sorties audio** — without `expectedOutputDeviceNames`: is the Mac's built-in output visible to CoreAudio (a basic hardware sanity check). With it: is the current default output exactly that device (or the combined Multi-Output Device when there are several).
- **MIDI** — is at least one MIDI device (e.g. the IAC Driver) online.
- **UAD Console** — is UAD Console running with the session named after `uadConsoleSession`'s filename open; shows the session that's actually open when it doesn't match. Requires granting this app Automation access to control "System Events" the first time (macOS will prompt) — without it, this indicator stays red.
- **Disques externes** — are the disks listed in `expectedExternalDiskNames` mounted.
- **Alimentation USB** — any connected USB device (hub or drive) currently drawing more current than its port supplies, the classic sign of a hub that isn't plugged into the wall. This one is the least field-tested part of the app (see note below).

### Known rough edges to validate on real hardware

A few pieces here were written without a Mac to test against and are the first place to look if something doesn't line up:

- The exact CoreAudio dictionary keys used to build the Multi-Output Device (`Sources/StudioSwitchCore/Audio/CoreAudioMultiOutputDeviceProvider.swift`).
- UAD Console's window-title format, which the "UAD Console" check matches against (`Sources/StudioSwitchCore/Health/AppleScriptUADConsoleSessionInspector.swift`).
- The USB power check's field lookup, which matches on key *content* rather than an exact key name specifically because `system_profiler`'s plain-text field labels are localized to the system's language (`Sources/StudioSwitchCore/Health/SystemProfilerUSBPowerProvider.swift`).
