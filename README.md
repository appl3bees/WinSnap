# WinSnap

Windows 11–style window snapping for macOS. Lives in the menu bar. It never connects to the internet.

## Install

1. Download `WinSnap-vX.Y.Z.zip` from the [latest release](https://github.com/appl3bees/WinSnap/releases/latest) and unzip it.
2. Move **WinSnap.app** to your Applications folder and open it.
3. macOS will say it can't verify the app, because WinSnap isn't notarized by Apple. Click **Done**, then go to
   **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to WinSnap, and confirm.
4. Allow WinSnap under **System Settings → Privacy & Security → Accessibility** when it asks.
   This is what lets it move other apps' windows.

Requires macOS 13 or later, on Apple silicon or Intel. When you install a newer version, macOS may ask you to
allow Accessibility again: remove the old WinSnap entry from that list and allow the new one.

## Build & run

```sh
./build.sh            # builds WinSnap.app in this folder
./build.sh --install  # also copies it to /Applications and launches it
```

On first launch, allow WinSnap under **System Settings → Privacy & Security → Accessibility**.
It starts working within a second of being allowed; no restart needed. If access is later revoked,
the menu bar icon turns into a warning and WinSnap resumes by itself once it's allowed again.

### Keeping Accessibility access across rebuilds

macOS ties the permission to the app's code signature. An ad-hoc signature changes with every build,
so each rebuild silently loses access. Create a local signing certificate once:

```sh
scripts/create-signing-cert.sh
./build.sh --install
```

`build.sh` signs with it from then on (set `WINSNAP_SIGN_IDENTITY` to use another identity).
After switching from ad-hoc, remove the old WinSnap entry from the Accessibility list
(or run `tccutil reset Accessibility com.winsnap.app`) and allow it one last time.

## Tests

```sh
swift test            # with Xcode
./build.sh --test     # also works with only the Command Line Tools
```

CI runs both the tests and the app build on every push and pull request.

## Releasing

Push a version tag and GitHub Actions builds a universal (Apple silicon + Intel) app, zips it and
publishes it as a GitHub Release:

```sh
git tag v1.0.0
git push origin v1.0.0
```

## Features

| Action | Result |
| --- | --- |
| Drag a window to the **top centre** | A pill appears and expands into the 6 snap layouts; release over a zone |
| Drag to the **top edge** (away from the flyout) | Maximize |
| Drag to the **left / right edge** | Left / right half |
| Drag to a **corner** | Quarter |
| **Hover the green button** | Snap layout flyout opens beside the macOS menu; hover a zone to preview it, click to snap |
| Drag a snapped window away | Restores its previous size |
| After snapping | **Snap Assist** offers your other windows for the empty zones (Esc or click away to skip) |
| ⌃⌥← / ⌃⌥→ | Snap left / right (again: move to the next display) |
| ⌃⌥↑ | Maximize, or half → top quarter |
| ⌃⌥↓ | Restore, half → bottom quarter, or minimize |
| ⌃⌥Z | Open snap layouts for the focused window |

Each feature can be switched off from the menu bar icon, which also has **Launch at Login**.
