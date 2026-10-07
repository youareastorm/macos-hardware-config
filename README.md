# macos-hardware-config
macOS hardware detection and configuration utility

## StudioSwitch

StudioSwitch is a macOS menu-bar app that detects which Universal Audio interface is connected and configures macOS audio for it: default input/output, an optional combined Multi-Output Device, and the active monitor channel pair (e.g. always `VIRTUAL 1 / VIRTUAL 2`). It also makes sure UAD Console is running with the profile's session (e.g. `OCTO EMPTY` at the studio). It does all this by itself when the interface is plugged in, and can launch a DAW from the same menu.

### Prerequisites

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)
- UAD Console (tested with 1.3.1) and the target DAWs installed (Logic Pro, Ableton Live, Pro Tools, Cubase, Bitwig Studio)

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

### Permissions (UAD Console)

Driving UAD Console needs two macOS permissions for StudioSwitch:

- **Automation → System Events**: macOS asks the first time. Survives rebuilds.
- **Accessibility** (System Settings → Privacy & Security → Accessibility): needed to read UAD Console's window title and drive its File > Open menu. Add `/Applications/StudioSwitch.app` with "+" and make sure it is on.

**After every rebuild the Accessibility permission silently stops working.** The bundle is ad-hoc signed, so each build has a new code identity, and macOS keeps the old entry (still shown as enabled) while refusing the new binary (`tccd: Failed to match existing code requirement … kTCCServiceAccessibility`). Toggling the switch off/on is not enough. Fix:

```bash
tccutil reset Accessibility com.simonrenard.studioswitch
```

then add the app again with "+" in Privacy & Security → Accessibility, and relaunch StudioSwitch (removing the permission quits the app). Without this, UAD Console is launched but its session never switches. A stable signing identity (a local code-signing certificate) would remove this step; not set up yet.

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

- `uadConsoleSession`: the `.uadmix` session UAD Console should have open for this profile (e.g. `~/Documents/Universal Audio/Sessions/OCTO EMPTY.uadmix`).
- `expectedClockSource`: the clock UAD Console should be on (e.g. `"Internal"`), as offered by the UA Mixer Engine for the connected unit. Omit to leave the clock alone.
- `expectedMonitorLevel`: UAD Console's MONITOR level in dB, from -96 to 0 (e.g. `-35` at home, `0` at the studio). Set once on activation; you can turn it afterwards. Omit to leave it alone.
- `hideUADOfflineDevices`: `true` to keep UAD Console's View > Offline Devices unchecked, so units that aren't connected (e.g. the studio's Apollo x8 at home) aren't shown after the connected unit's channels.

`expectedUADConsoleSessionNames` and `expectedExternalDiskNames` are still part of the file format but currently unused (see "What was removed").

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
- Makes sure UAD Console runs with `uadConsoleSession` open (details below).
- Then, with `hideUADOfflineDevices`, unchecks View > Offline Devices if needed, and with `expectedClockSource` / `expectedMonitorLevel`, sets the clock and the monitor level (details below). These come after the session so loading it can't override them.

A step that fails is reported in the menu without blocking the others.

### UAD Console session

On activation, StudioSwitch:

- **does nothing** if UAD Console already shows the profile's session (exact name, ignoring case and the unsaved-changes `*`);
- **switches** it through UAD Console's own File > Open menu (System Events UI scripting) if another session is open: it waits for the Open panel (it can take several seconds to appear), uses "Go to Folder" to type the path, waits for the panel to close, and confirms the load in UAD Console's own log (`Hide Progress Dialog` in `~/Library/Logs/Universal Audio/UAD Console_*.txt`) — about 8 s. The window title isn't used for this: read through System Events it can stay stale after a load (seen after a reboot: "empty home" loaded, title still "home guit vox*"), which made StudioSwitch report a false failure;
- **cold start**: if UAD Console isn't running, launches it, waits for its session window (up to 40 s), then switches the same way — about 13 s.

Any step that doesn't happen raises an error shown in orange in the menu, instead of failing silently. Things found on real hardware (UAD Console 1.3.1) that shaped this:

- A running UAD Console ignores requests to open another session file (`NSWorkspace` open, a direct Apple Event `open`); scripted `quit` is refused (-128).
- Launching UAD Console *with* a session file doesn't load it either: it starts on its default session.
- The Open panel appears with a delay; typing before it's there sends the keystrokes elsewhere and nothing loads (the cause of earlier failures).
- `NSAppleScript` must run on the main thread; StudioSwitch runs its scripts there even when activation happens in the background.
- With unsaved changes in the open session (UA Mixer Engine `Dirty` flag, or `*` in the window title), File > Open... first shows UAD Console's own "save changes?" question. It's drawn by Console itself (`Rack_Question` in `~/Library/Logs/Universal Audio/UAD Console_*.txt`), not a macOS window, so System Events can't see or click it; it blocked the switch after a reboot until clicked by hand. StudioSwitch now presses Escape when it's up, which closes it **without saving** (verified: session file byte-identical, `Dirty` back to false) and lets the Open panel come. Earlier notes here said switching discarded changes without asking: that was wrong in this case.

### UAD clock, monitor level and offline units

The clock and the monitor level go through the **UA Mixer Engine**, the background process UAD Console itself drives, on its local control port (127.0.0.1:4710). It answers `get <path>` with JSON (null-terminated) and takes `set <path>/value <v>`. What StudioSwitch uses:

- `/` → `ClockSource` (with the list of `values` the connected unit offers: only `Internal` on an Apollo Solo) and `SampleRate`.
- `/devices/N` → `DeviceName`, `DeviceOnline` (the studio's Apollo x8 is listed offline at home).
- `/devices/N/outputs/M` with `IOType` = `Monitor` → `CRMonitorLevel` in dB (-96…0): the MONITOR knob.

Each check or activation uses **one** connection: the engine (11.9.0) crashed (segfault in `Ntwk_Socket_Server::createConnectionObject`) when sent a burst of short-lived connections. It isn't restarted automatically after a crash (its launch agent only runs at login): `launchctl kickstart gui/$(id -u)/com.uaudio.ua_mixer_engine`.

"Offline Devices" is a UAD Console preference, not an engine property. Its state is read from `"Show Offline Devices"` in `~/Library/Preferences/Universal Audio/UAD ConsolePrefs.json` (Console rewrites it within 0.2 s of a click), and it is unchecked by clicking the View menu item with System Events (needs UAD Console running and the Accessibility permission). The menu's own check mark isn't read: it only refreshes when the menu is opened.

### Menu-bar icon

The icon turns into a warning triangle as soon as a health check isn't green or the last activation (automatic or clicked) had an error, so a problem shows without opening the menu. The checks re-run every 60 s in the background (no UAD Console window is touched; one UA Mixer Engine connection per pass). The menu also shows the last automatic activation's errors.

### Activation log

Every automatic evaluation and every activation (automatic or from the menu) is written to `~/Library/Logs/StudioSwitch/activation.log`, one timestamped line per event (open it in Console.app or `tail -f`). It records: app start, each device-list change macOS signals, for each profile whether its Thunderbolt hardware and CoreAudio device are online, the decision (activate / already active / nothing ready), then each activation step with its duration and error, the output channel pair before and after it is set and once more at the very end (after UAD Console), the Offline Devices state, and the UA Mixer Engine clock and monitor level before and after. The file is moved to `activation.log.1` past 1 MB.

### Health indicators

After activating a profile (or when opening the menu, for whichever profile matches the connected hardware) the menu shows one row per check: a colored dot (green/yellow/red), the check's name, and a dropdown of the real alternatives. Picking one applies it immediately and re-runs the checks; "Actualiser" re-runs them without reactivating.

- **Interface audio** — is `audioDeviceName` online, at the expected sample rate, and the default input (and output, when the profile has no separate `expectedOutputDeviceNames`).
- **Sortie HP** — without `expectedOutputDeviceNames`: is the Mac's built-in output visible (a basic sanity check). With it: is the current default output exactly that device. Clicking the row's name opens Audio MIDI Setup.
- **Canaux de sortie** — only when `expectedOutputChannelNames` is set: is that channel pair currently active. Dropdown: every consecutive channel pair the device reports.
- **Clock** — only with `expectedClockSource`: red with the current clock when it differs.
- **Volume moniteur** — only with `expectedMonitorLevel`: yellow with the current level when it differs (you may have turned it on purpose).
- **Cartes hors ligne** — only with `hideUADOfflineDevices`: red when View > Offline Devices is checked.

These three rows have no dropdown.

### What was removed

The menu used to also show UAD Console, MIDI, USB power and external-disk rows. They were taken out to focus on audio configuration; the code mostly remains but is no longer wired in.

- **UAD Console row**: the health row and its session picker are gone from the menu; UAD Console is now handled by activation only (see above). The per-profile whitelist of accepted sessions (`expectedUADConsoleSessionNames`) is unused.
- **USB topology, wattage and power-fault detection**: see `docs/usb-diagnostics.md` and `Scripts/usb-topology.py`. The IOKit disconnect detector, the `system_profiler` power provider and the disk inspector remain in the codebase, unused.

### Next try (studio)

- Check on the Apollo x8 that setting the clock through the engine works: on an Apollo Solo, `Internal` is the only clock offered, so a clock *change* has not been seen yet. The exact `set` value format for a string (`Internal`) is unverified.
- Check that the monitor goes to 0 dB on plug-in.
- Monitor channel pair: launching UAD Console resets it to MON L / MON R (seen in the activation log after a reboot); StudioSwitch now re-checks it after the UAD steps and puts it back (verified at home).
- Home: when UAD Console starts, a 48V confirmation dialog can appear; StudioSwitch should click OK on it at Home (not done yet).
- Seen once on the first launch after a rebuild, before a reboot fixed it: Console stayed on "New Session" at 44.1 kHz, its window title had no session name (just "UAD Console", so the session switch can't confirm), and the engine listed both units offline. Not diagnosed; watch for it.

### Validated on real hardware

Verified on an Apollo Solo (home) and a Thunderbolt 3 Option Card interface (studio): detection, default input/output, Multi-Output Device creation/reuse/name-collision detection, the monitor channel pair being forced to `VIRTUAL 1 / VIRTUAL 2` on activation, activation at launch, automatic activation after unplugging and replugging the interface, and the UAD Console session: switch while running (both directions), no-op when already open, cold start, and the full studio scenario (session changed, UAD Console closed, interface unplugged and replugged → UAD Console relaunched on `OCTO EMPTY`).

Also verified on the Apollo Solo: reading the clock and monitor level from the UA Mixer Engine, setting the monitor level (-28 → -35 dB, -34 → -35 dB, shown on Console's knob), and unchecking Offline Devices (checked → unchecked, confirmed in `ConsolePrefs.json`). After a reboot with StudioSwitch in Login Items, the whole Home setup came back on its own (session `empty home`, Offline Devices unchecked, clock, monitor level, VIRTUAL 1/2).

Not verified: changing the clock source (see "Next try"), the IAC Driver step, DAW launching with a template, and the consecutive-pair assumption on interfaces other than the two above (stereo pairs are assumed to be consecutive channel numbers: 1/2, 3/4, …).
