import AppKit
import Carbon.HIToolbox
import ServiceManagement

enum Settings {
    private static let d = UserDefaults.standard

    static let toggles: [(key: String, title: String)] = [
        ("dragSnap", "Snap When Dragging to Screen Edges"),
        ("topFlyout", "Show Snap Layouts at Top of Screen"),
        ("greenButton", "Show Snap Layouts on Green Button Hover"),
        ("snapAssist", "Snap Assist (Suggest Windows to Fill Layout)"),
        ("hotkeys", "Keyboard Shortcuts (⌃⌥ + Arrows, ⌃⌥Z)"),
    ]

    static func register() {
        d.register(defaults: Dictionary(uniqueKeysWithValues: toggles.map { ($0.key, true) }))
    }

    static subscript(key: String) -> Bool {
        get { d.bool(forKey: key) }
        set { d.set(newValue, forKey: key) }
    }

    static var dragSnap: Bool { self["dragSnap"] }
    static var topFlyout: Bool { self["topFlyout"] }
    static var greenButton: Bool { self["greenButton"] }
    static var snapAssist: Bool { self["snapAssist"] }
    static var hotkeys: Bool { self["hotkeys"] }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let drag = DragSnapController()
    private let green = GreenButtonController()
    private var trustTimer: Timer?
    private var trustWatch: Timer?
    private var running = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.register()
        setUpStatusItem()
        if AXIsProcessTrusted() {
            startAll()
        } else {
            requestAccess()
        }
    }

    private func requestAccess() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        waitForAccess()
    }

    private func waitForAccess() {
        updateIcon()
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard AXIsProcessTrusted() else { return }
            t.invalidate()
            self?.startAll()
        }
    }

    private func startAll() {
        running = true
        drag.start()
        green.start()
        applyHotkeys()
        updateIcon()
        // Access can be revoked while we run (switched off, or reset after the signature changed).
        // Without it every AX call fails silently, so stand down and wait for it to come back.
        trustWatch?.invalidate()
        trustWatch = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard !AXIsProcessTrusted() else { return }
            NSLog("WinSnap: Accessibility access was revoked; pausing until it is granted again")
            self?.stopAll()
            self?.waitForAccess()
        }
    }

    private func stopAll() {
        running = false
        trustWatch?.invalidate()
        trustWatch = nil
        drag.stop()
        green.stop()
        HotKeyManager.shared.unregisterAll()
    }

    private func updateIcon() {
        let trusted = AXIsProcessTrusted()
        let image = NSImage(systemSymbolName: trusted ? "rectangle.split.2x2" : "exclamationmark.triangle",
                            accessibilityDescription: "WinSnap")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = trusted ? "WinSnap" : "WinSnap needs Accessibility access"
    }

    private func applyHotkeys() {
        let hk = HotKeyManager.shared
        hk.unregisterAll()
        guard Settings.hotkeys else { return }
        let mods = controlKey | optionKey
        hk.register(keyCode: kVK_LeftArrow, modifiers: mods) { KeyboardSnap.handle(.left) }
        hk.register(keyCode: kVK_RightArrow, modifiers: mods) { KeyboardSnap.handle(.right) }
        hk.register(keyCode: kVK_UpArrow, modifiers: mods) { KeyboardSnap.handle(.up) }
        hk.register(keyCode: kVK_DownArrow, modifiers: mods) { KeyboardSnap.handle(.down) }
        hk.register(keyCode: kVK_ANSI_Z, modifiers: mods) { [weak self] in self?.showFlyoutForFocusedWindow() }
    }

    /// Like Win+Z: open the layout flyout under the focused window's green button.
    private func showFlyoutForFocusedWindow() {
        guard let w = AX.focusedWindow(), !w.isOwn, let f = w.frame else { return }
        let window = Coords.flip(f)
        let anchor = w.zoomButton.flatMap(AX.cocoaFrame(of:))
            ?? CGRect(x: window.minX + 60, y: window.maxY - 26, width: 14, height: 14)
        green.showFlyout(for: w, anchor: anchor, sticky: true)
    }

    // MARK: Menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: "WinSnap", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if !AXIsProcessTrusted() {
            menu.addItem(item("⚠︎ Grant Accessibility Access…", #selector(openAccessibilitySettings)))
        }
        menu.addItem(.separator())

        for t in Settings.toggles {
            let mi = item(t.title, #selector(toggle(_:)))
            mi.representedObject = t.key
            mi.state = Settings[t.key] ? .on : .off
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        let shortcuts = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for line in ["⌃⌥←  Snap left / move left", "⌃⌥→  Snap right / move right",
                     "⌃⌥↑  Maximize / snap to top quarter", "⌃⌥↓  Restore / bottom quarter / minimize",
                     "⌃⌥Z  Open snap layouts"] {
            let mi = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            mi.isEnabled = false
            sub.addItem(mi)
        }
        shortcuts.submenu = sub
        menu.addItem(shortcuts)

        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit WinSnap", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return mi
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        Settings[key].toggle()
        if key == "hotkeys", running { applyHotkeys() }
        if key == "greenButton", !Settings.greenButton { green.hideFlyout() }
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("WinSnap: launch at login failed: \(error)")
        }
    }

    @objc private func openAccessibilitySettings() {
        requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
