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

Two optional fields let a profile drive the health indicators (see below):

- `expectedSampleRate`: nominal sample rate in Hz the audio interface should be running at (e.g. `96000`). Omit or leave `null` to skip this check.
- `expectedExternalDiskNames`: volume names of external disks that should be mounted for this profile (e.g. `["Samples", "Backup"]`). Omit or leave `[]` to skip this check.

### Health indicators

Clicking a profile in the menu bar runs a set of status checks and shows a colored dot per item: green (OK), yellow (warning), red (error).

- **Interface audio** — is the configured audio device online, at the expected sample rate, and set as the default input/output.
- **Haut-parleurs Mac** — is the Mac's built-in output device visible to CoreAudio.
- **MIDI** — is at least one MIDI device (e.g. the IAC Driver) online.
- **Disques externes** — are the disks listed in `expectedExternalDiskNames` mounted.

Use the "Actualiser" button under the indicators to re-run the checks without reactivating the profile.
