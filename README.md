# WinSnap

Windows 11–style window snapping for macOS. Lives in the menu bar.

## Build & run

```sh
./build.sh            # builds WinSnap.app in this folder
./build.sh --install  # also copies it to /Applications and launches it
```

On first launch, allow WinSnap under **System Settings → Privacy & Security → Accessibility**.
It starts working within a second of being allowed; no restart needed.

### Keeping the permission across rebuilds

macOS ties the Accessibility permission to the app's signing identity, so `build.sh` signs with a
stable certificate when it finds one, in this order:

1. `$WINSNAP_SIGN_IDENTITY` (a certificate name or SHA-1 hash from `security find-identity -v -p codesigning`)
2. A **Developer ID Application** or **Apple Development** certificate in your keychain
3. **WinSnap Local Signing**, a self-signed certificate you create once with:

   ```sh
   ./make-cert.sh   # asks for your password to trust the certificate
   ```

With none of these it falls back to an ad-hoc signature and prints a warning; macOS then asks again
after every rebuild. When you first switch to a certificate, remove the old WinSnap entry under
Accessibility and allow it once more; after that, rebuilds keep the permission.

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
