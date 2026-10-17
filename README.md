# WinSnap

Windows 11–style window snapping for macOS. Lives in the menu bar.

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

## Features

| Action | Result |
| --- | --- |
| Drag a window to the **top centre** | A pill appears and expands into the 6 snap layouts; release over a zone |
| Drag to the **top edge** (away from the flyout) | Maximize |
| Drag to the **left / right edge** | Left / right half |
| Drag to a **corner** | Quarter |
| **Hover the green button** | Snap layout flyout; click a zone |
| Drag a snapped window away | Restores its previous size |
| After snapping | **Snap Assist** offers your other windows for the empty zones (Esc or click away to skip) |
| ⌃⌥← / ⌃⌥→ | Snap left / right (again: move to the next display) |
| ⌃⌥↑ | Maximize, or half → top quarter |
| ⌃⌥↓ | Restore, half → bottom quarter, or minimize |
| ⌃⌥Z | Open snap layouts for the focused window |

Each feature can be switched off from the menu bar icon, which also has **Launch at Login**.
