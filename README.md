# WinSnap

Windows 11–style window snapping for macOS. Lives in the menu bar.

## Build & run

```sh
./build.sh            # builds WinSnap.app in this folder
./build.sh --install  # also copies it to /Applications and launches it
```

On first launch, allow WinSnap under **System Settings → Privacy & Security → Accessibility**.
It starts working within a second of being allowed; no restart needed.
The app is ad-hoc signed, so after a rebuild macOS may ask again: remove the old entry and re-add it.

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

## Tests

```sh
swift test   # unit tests for the layout maths and keyboard shortcuts
```

CI runs the tests and `./build.sh` on every push.
