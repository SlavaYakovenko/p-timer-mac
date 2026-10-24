# p-timer-mac

A minimalistic work/break timer for the macOS menu bar.

- 25 minutes of work, then a 5-minute break.
- Work starts only manually; the break starts automatically when work ends.
- Lives only in the menu bar, showing just `MM:SS` with no icon. No windows, no Dock icon, no notifications.
- A short sound plays at the end of each interval.
- The menu shows how many work intervals you completed today.
- About 260 KB, no dependencies. Universal: Apple Silicon and Intel, macOS 13+.

<img src="docs/p-timer-mac-promo.png" width="600" alt="p-timer-mac in the menu bar with its menu open">

## Installation

1. Download `p-timer-mac.dmg` from [Releases](https://github.com/SlavaYakovenko/p-timer-mac/releases), open it and drag `p-timer-mac` into `Applications`.
2. Launch it. `25:00` appears in the menu bar.

The app is ad-hoc signed (no Apple Developer ID), so macOS may block a downloaded DMG on first launch. If so, right-click the app → Open, or run
`xattr -dr com.apple.quarantine /Applications/p-timer-mac.app`.

Launch at login: System Settings → General → Login Items → add p-timer-mac.

Only one copy runs at a time: launching it again does nothing.

## Usage

Click the timer in the menu bar to open the menu:

- **Start / Resume** — start the timer, or continue after a pause;
- **Stop** — pause;
- **Reset** — reset to 25:00;
- **Completed today: N** — how many 25-minute work intervals were fully completed today (informational; resets at midnight);
- **Quit** — quit.

When the 25 minutes of work run out, a sound plays and the 5-minute break starts right away (its time is shown in gray). When the break ends, the sound plays again, the timer returns to 25:00 and waits to be started manually.

## Building

Only Xcode Command Line Tools are required (`xcode-select --install`).

```sh
./build.sh
```

Output:

- `build/p-timer-mac.app` — the app (~260 KB, ~90 KB of which is the icon);
- `build/p-timer-mac.dmg` — the installer image (~240 KB).
