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
- `expectedExternalDiskNames`: volume names of external disks expected for this profile (e.g. `["Samples", "Backup"]`). Drives the "Disques externes" disclosure (see below), not a colored indicator. Omit or leave `[]` to hide it.
- `expectedOutputDeviceNames`: the device(s) the Mac's audio *output* should route to, separately from `audioDeviceName` (which is only the input/recording interface once this is set). One entry selects that device as the default output; two or more (e.g. `["Virtuel 1", "Virtuel 2"]`) make StudioSwitch create and select a combined Multi-Output Device the first time the profile is activated, and reuse it afterwards. Omit or leave `[]` to keep `audioDeviceName` as both input and output.
- `expectedOutputChannelNames`: exactly two channel names `audioDeviceName` should have as its active output pair (e.g. `["VIRTUAL 1", "VIRTUAL 2"]`), for interfaces with more outputs than one stereo pair (a UA Apollo routed to its software-return channels instead of its main outs). Distinct from `expectedOutputDeviceNames`, which combines separate CoreAudio devices — this checks a pair *within* one device. Omit or leave `[]` to skip this check.

### Automatic setup on activation

Clicking a profile doesn't just detect state — it actively applies it:

- Sets the default input (and, without an `expectedOutputDeviceNames`, the output too) to `audioDeviceName`.
- When `expectedOutputDeviceNames` is set, creates/reuses the Multi-Output Device and sets it as the default output.
- Opens the profile's UAD Console session (`uadConsoleSession`). If a different session is already open, this currently just re-sends an "open" request to UAD Console — it does not quit/relaunch it, so if UAD Console ignores that request while another session is loaded, the "UAD Console" indicator below will still show red until you switch the session yourself.
- Enables the IAC Driver when `useIACDriver` is set.

Any step that fails is reported next to the profile buttons without blocking the others (e.g. a bad UAD Console path won't stop the audio device from being set).

### Health indicators

Clicking a profile (or just opening the app, for whichever profile matches the currently connected hardware) shows one row per check: a colored dot (green/yellow/red), the check's name, and — on the same line, right-aligned — a dropdown of the real alternatives currently detected. Picking one applies it immediately (sets the device, opens the session, writes the channel pair, …) and re-runs every check. "Actualiser" re-runs them without reactivating the profile.

- **Interface audio** — is `audioDeviceName` online, at the expected sample rate, and set as the default input (and output, when the profile has no separate `expectedOutputDeviceNames`). Dropdown: every connected CoreAudio device; picking one sets it as the default input (and output too, unless the profile routes output separately).
- **Sorties audio** — without `expectedOutputDeviceNames`: is the Mac's built-in output visible to CoreAudio (a basic hardware sanity check). With it: is the current default output exactly that device (or the combined Multi-Output Device when there are several). Dropdown: every connected device; picking one sets it as the default output.
- **MIDI** — is at least one MIDI device (e.g. the IAC Driver) online. Dropdown: the online devices, plus "IAC Driver" when it isn't already one of them; picking an entry brings that device online (`kMIDIPropertyOffline` → 0).
- **UAD Console** — is UAD Console running with the session named after `uadConsoleSession`'s filename open; shows the session that's actually open when it doesn't match. Requires granting this app Automation access to control "System Events" the first time (macOS will prompt) — without it, this indicator stays red. Dropdown: every `.uadmix` file in `~/Documents/Universal Audio/Sessions`, currently-open one first; picking one opens it in UAD Console.
- **Canaux de sortie** — only shown when `expectedOutputChannelNames` is set: is that channel pair currently active on `audioDeviceName`. Dropdown: every consecutive channel pair the device reports (1/2, 3/4, …); picking one writes it as the device's preferred stereo pair.
- **Alimentation USB** — a static `system_profiler` snapshot can't see a power problem (see the class's doc comment: unplugging a hub's wall adapter produced no change in its reported fields), because a power fault is an *event*, not a persisted state. So this instead reads the last 15 minutes of the unified log (`log show`, the same source Console.app's "USB" filter uses) for lines that look power-related — explicit wording ("power", "current", "not enough…") or a device resetting/detaching/reconnecting, the churn a starved device produces even when nothing ever says "power". Red + the matching lines as detail when found; otherwise falls back to the enumeration/wattage check. This is a heuristic first pass over the same raw evidence a person would read in Console.app to diagnose a failing drive, not a definitive per-device verdict — its dropdown is informational only, since there's no fix action to apply from a log line.

Below the checks, a separate "Disques externes" row (no colored dot) expands on click to show only the disks from `expectedExternalDiskNames` that are actually mounted right now, each with its USB device's wattage when macOS reports it (or "non remonté par macOS"). Disks that are expected but absent are simply left off the list. The disk ↔ USB-device correlation (substring match, since `diskutil` and `system_profiler` truncate device names differently) is the same logic as `Scripts/usb-topology.py`, which you can run standalone to double check it against reality.

### Known rough edges to validate on real hardware

A few pieces here were written without a Mac to test against and are the first place to look if something doesn't line up:

- The exact CoreAudio dictionary keys used to build the Multi-Output Device (`Sources/StudioSwitchCore/Audio/CoreAudioMultiOutputDeviceProvider.swift`).
- The channel-pair enumeration and the `kAudioDevicePropertyPreferredChannelsForStereo` write (`Sources/StudioSwitchCore/Health/CoreAudioStatusProvider.swift`'s `availableOutputChannelPairs`, `Sources/StudioSwitchCore/Audio/AudioMIDIConfigurator.swift`'s `setPreferredOutputChannelPair`) — assumes an interface's stereo pairs are always consecutive channel numbers (1/2, 3/4, …), the standard convention but not verified against every interface.
- The `log show --predicate` used by `Sources/StudioSwitchCore/Health/LogShowUSBKernelLogInspector.swift` and the keyword list in `KernelLogUSBPowerFaultDetector` — the command and predicate syntax are standard, but the exact wording of real USB power-fault kernel messages on your hardware/macOS version hasn't been checked against real output yet. If it never fires even when you know a device is power-cycling, run `log show --last 15m --style compact --predicate '(subsystem CONTAINS[c] "usb") OR (process == "kernel" AND eventMessage CONTAINS[c] "usb")'` yourself, look at the real lines, and adjust the keyword list (or the predicate) to match.
