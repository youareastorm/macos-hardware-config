# macos-hardware-config
macOS hardware detection and configuration utility

## StudioSwitch

StudioSwitch is a macOS menu-bar app that detects which Universal Audio interface is connected and configures macOS audio for it: default input/output, an optional combined Multi-Output Device, and the active monitor channel pair (e.g. always `VIRTUAL 1 / VIRTUAL 2`). It does this by itself when the interface is plugged in, and can launch a DAW from the same menu.

### Prerequisites

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)
- The target DAWs installed (Logic Pro, Ableton Live, Pro Tools, Cubase, Bitwig Studio)

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

This produces `StudioSwitch.app` at the repo root. Move it to `/Applications`, then add it to Login Items (System Settings → General → Login Items) to have it launch automatically. The bundle is ad-hoc signed; the app no longer needs any special macOS permission (no Automation or Accessibility), so rebuilding it doesn't require re-granting anything.

### Configuration

StudioSwitch creates `~/Library/Application Support/StudioSwitch/profiles.json` on first run with two profiles ("Home" and "Studio"). Edit this file; it is read when the menu loads and on every automatic evaluation, so config changes need no rebuild (restart the app if the menu still shows old profiles).

Each profile needs two names, found in two different places:

- `deviceNameMatch` — how the interface is *detected*. Matched against the `Device Name` lines of `system_profiler SPThunderboltDataType`, **exactly** (case-insensitive, not a substring). This is the name of the Thunderbolt device, which is not always the Apollo model: an Apollo Solo shows up as `Apollo Solo`, while a rack unit with the Thunderbolt option card shows up as `Thunderbolt 3 Option Card`. Find yours with:

  ```bash
  system_profiler SPThunderboltDataType | grep "Device Name"
  ```

- `audioDeviceName` — the CoreAudio device the audio settings are applied to (usually `Universal Audio Thunderbolt`). Find it with:

  ```bash
  system_profiler SPAudioDataType | grep -E "^\s+[A-Za-z].*:$"
  ```

The seeded "Studio" profile uses the placeholder `"Apollo"` for `deviceNameMatch`, which will not match real hardware until you replace it.

Optional fields:

- `expectedOutputChannelNames`: exactly two channel names the interface should have as its active output pair (e.g. `["VIRTUAL 1", "VIRTUAL 2"]`), for interfaces with many outputs. StudioSwitch writes this pair as the device's preferred stereo output on activation. The names must match what the interface reports (`MON L / MON R`, `LINE 1 / LINE 2`, `VIRTUAL 1 / VIRTUAL 2`, …); omit or leave `[]` to leave the pair alone.
- `expectedOutputDeviceNames`: the device(s) the Mac's audio *output* should route to, separately from `audioDeviceName` (which then only handles input). One entry selects that device as the default output; two or more (e.g. `["Virtuel 1", "Virtuel 2"]`) make StudioSwitch create and select a combined Multi-Output Device on first activation, and reuse it afterwards. Omit or leave `[]` to keep `audioDeviceName` as both input and output.
- `expectedSampleRate`: sample rate in Hz the interface should be running at. **Only checked, not applied**: a mismatch shows a warning on "Interface audio".
- `useIACDriver`: enable the IAC Driver on activation (not yet verified on real hardware).
- `daws`: the DAWs offered in the menu (`name`, `bundleID`, optional `appPath` and `templatePath` — a project/template file to open the DAW with).

`uadConsoleSession`, `expectedUADConsoleSessionNames` and `expectedExternalDiskNames` are still part of the file format but currently unused (see "What was removed").

### Automatic switching

StudioSwitch activates the matching profile on its own, without a click:

- once at launch, if the interface is already connected;
- whenever the list of CoreAudio devices changes (the interface plugged in, powered on, or removed), after a 2 s settling delay.

It only acts when the *matched profile changes* (including from "none" to one), so unrelated device events — headphones, or the Multi-Output Device it creates itself — never re-apply a profile over a manual change. A profile counts as matched only when both its Thunderbolt hardware and its CoreAudio device are online (the two can appear at different moments); if configuring the device fails, it is retried on the next change.

The **"Bascule auto au branchement"** checkbox in the menu turns this off (on by default, remembered between launches).

### What activation applies

Clicking a profile in the menu, or an automatic activation, does the same thing:

- Sets the default input (and, without `expectedOutputDeviceNames`, the output and system output too) to `audioDeviceName`.
- With `expectedOutputDeviceNames`, creates/reuses the Multi-Output Device and sets it as the default output.
- With `expectedOutputChannelNames`, writes that channel pair as the interface's active stereo output.
- Enables the IAC Driver when `useIACDriver` is set.

A step that fails is reported in the menu without blocking the others.

### Health indicators

After activating a profile (or when opening the menu, for whichever profile matches the connected hardware) the menu shows one row per check: a colored dot (green/yellow/red), the check's name, and a dropdown of the real alternatives. Picking one applies it immediately and re-runs the checks; "Actualiser" re-runs them without reactivating.

- **Interface audio** — is `audioDeviceName` online, at the expected sample rate, and the default input (and output, when the profile has no separate `expectedOutputDeviceNames`).
- **Sortie HP** — without `expectedOutputDeviceNames`: is the Mac's built-in output visible (a basic sanity check). With it: is the current default output exactly that device. Clicking the row's name opens Audio MIDI Setup.
- **Canaux de sortie** — only when `expectedOutputChannelNames` is set: is that channel pair currently active. Dropdown: every consecutive channel pair the device reports.

### What was removed

The menu used to also show UAD Console, MIDI, USB power and external-disk rows. They were taken out to focus on audio configuration; the code mostly remains but is no longer wired in.

- **UAD Console control**: switching the session of an already-running UAD Console never became reliable. It ignores `NSWorkspace`/Apple Event requests to open another session; the only mechanism that worked was scripting its File > Open menu through System Events, which needs Automation and Accessibility permissions (and Accessibility is invalidated by every ad-hoc rebuild). It worked from a Terminal script and once inside the app, then regressed without a root cause being found. The classes remain under `Sources/StudioSwitchCore/UAD/` and `Health/AppleScriptUADConsoleSession*`, with the findings in their doc comments.
- **USB topology, wattage and power-fault detection**: see `docs/usb-diagnostics.md` and `Scripts/usb-topology.py`. The IOKit disconnect detector, the `system_profiler` power provider and the disk inspector remain in the codebase, unused.

### Validated on real hardware

Verified on an Apollo Solo (home) and a Thunderbolt 3 Option Card interface (studio): detection, default input/output, Multi-Output Device creation/reuse/name-collision detection, the monitor channel pair being forced to `VIRTUAL 1 / VIRTUAL 2` on activation, activation at launch, and automatic activation after unplugging and replugging the interface.

Not verified: the IAC Driver step, DAW launching with a template, and the consecutive-pair assumption on interfaces other than the two above (stereo pairs are assumed to be consecutive channel numbers: 1/2, 3/4, …).
