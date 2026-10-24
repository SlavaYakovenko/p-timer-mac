# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

p-timer-mac — minimal macOS menu-bar work/break timer. Everything in the project — code, comments, UI strings, docs — is in English. Hard requirements: menu bar only (no windows, no Dock icon, no popups/notifications; status item shows just `MM:SS`, no emoji/icon — menu-bar space is scarce), only a short sound at timer end, 25-min work timer starts **only manually**, 5-min break starts automatically after work, smallest possible memory/disk/distribution footprint. Keep it dependency-free.

Describe the app only as a work/break timer. Never name, link to or allude to any third-party time-management method or brand anywhere (code, comments, docs, icon, bundle id, commit messages), and add no trademark disclaimers — they would only draw attention to a brand the project has nothing to do with.

## Build

```sh
./build.sh   # -> build/p-timer-mac.app (universal arm64+x86_64, ad-hoc signed) and build/p-timer-mac.dmg
open build/p-timer-mac.app
```

Only Xcode Command Line Tools are needed. No Xcode project or SwiftPM: `build.sh` calls `swiftc` directly per arch, `lipo`s, strips, copies `Resources/Info.plist` and `Resources/AppIcon.icns`, ad-hoc `codesign`s, and builds an LZMA DMG with `hdiutil`. Deployment target is macOS 13 — lower targets fail to link for x86_64 because the installed Command Line Tools lack x86_64 Swift compatibility libs. Keep `LSMinimumSystemVersion` in Info.plist in sync with the `-target` in build.sh. `build.sh` prints the DMG and app sizes; current baseline is ~260 KB app (~90 KB of it the icon) and ~240 KB DMG (README.md quotes these numbers, so update it if they change noticeably).

Releases are cut with git-flow (`git flow release start v0.0.2` … `git flow release finish`, then push `main`, `develop` and the tag). The GitHub release is then created by hand from that tag, with hand-written notes — never auto-generated notes, and never create or edit releases yourself. Publishing it runs `.github/workflows/release.yml` (macos-15 runner), which sets `CFBundleShortVersionString`/`CFBundleVersion` from the tag (`v0.0.2` → `0.0.2`, build-only, not committed), runs `build.sh` and uploads `build/p-timer-mac.dmg` to that release. Versions are semver, tags are `v`-prefixed; the first release is `v0.0.1`. Keep the committed Info.plist version at the latest released version (it is what local builds report).

`Resources/AppIcon.icns` is committed as a finished asset (the source artwork and generator script are not kept in the repo). It holds only renditions up to 128pt/256px on purpose — the app has no Dock icon, and the gradient artwork's 512/1024px renditions alone would add >1 MB. The README image is `docs/p-timer-mac-promo.png` (not bundled).

There are no automated tests. To exercise the state machine quickly, compile a scratch copy of `Sources/main.swift` (into the scratchpad, not the repo) with the top-level `workDuration`/`breakDuration` constants shortened and scripted `perform(#selector(...))` calls; osascript/System Events can't inspect the menu bar without accessibility permission.

## Architecture

Everything is in `Sources/main.swift` (AppKit, `NSStatusItem`, `.accessory` activation policy + `LSUIElement`):
- Single instance: before `app.run()`, exits if another process with the same bundle id is running (covers copies in different locations, e.g. `build/` vs `/Applications`). It relies on `Bundle.main.bundleIdentifier`, so a bare `swiftc` binary run outside the .app skips the check.
- State: `phase` (`.work`/`.rest`), `remaining`, and `endDate` (non-nil ⇔ running). Countdown is computed from the absolute `endDate`, not by counting ticks, so sleep and menu tracking don't cause drift.
- The ticker `Timer` is added to the run loop in `.common` mode so the title keeps updating while the menu is open.
- `tick()` handles phase completion: plays system sound "Glass", work → auto-start break, break → back to idle work 25:00.
- Daily counter: `doneCount` of completed work phases, incremented in `tick()` when work ends (so a session ending after midnight counts for the new day). Persisted in `UserDefaults` (`doneCount`, `doneDay` = local calendar day as a `yyyymmdd` Int, so time-zone changes don't reset it); `rollDay()` zeroes it when the day changes and runs at launch, at work completion and in `menuWillOpen` (the app has `NSMenuDelegate`), so no midnight timer is needed. Shown only as a disabled menu item, never in the status bar.
- Closing the lid (`NSWorkspace.willSleepNotification`) pauses a running work session; a running break keeps counting.
- `render()` is the single place that updates the title and menu-item enabled state/titles (Start vs Resume); work time uses `labelColor`, break time `secondaryLabelColor`. "Paused"/"fresh" are decided by comparing whole displayed seconds against the phase duration, so stopping within the first second still shows Start, not Resume.
- The `UserDefaults` domain is the bundle id (`com.yakovenko.p-timer-mac`), so changing `CFBundleIdentifier` drops the saved daily count and changes the single-instance check.
- README.md's Usage section lists each menu item and describes how it behaves; update it whenever menu items or timer behavior change.
