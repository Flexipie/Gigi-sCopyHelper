//
//  AppDelegate.swift
//  GigiCopyHelper
//
//  Creates the menu bar item, requests Accessibility permission,
//  registers a global hotkey (Cmd+Shift+U), and captures clipboard text
//  by simulating Command+C in the frontmost app.
//

import Cocoa
import ApplicationServices
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKeyManager: HotKeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the process is trusted for Accessibility so we can send Cmd+C
        Accessibility.ensurePermissionPrompt()

        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "GigiCopyHelper") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "G"
            }
        }

        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "Capture Selection (⌘⇧U)", action: #selector(captureNow), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)

        let openItem = NSMenuItem(title: "Open Data Folder", action: #selector(openDataFolder), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit GigiCopyHelper", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu

        // Register global hotkey: Cmd + Shift + U
        hotKeyManager = HotKeyManager()
        hotKeyManager.register(keyCode: kVK_ANSI_U, modifiers: [.cmd, .shift]) { [weak self] in
            self?.captureNow()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func captureNow() {
        // Save clipboard, send Cmd+C to frontmost app, wait, read text, restore clipboard.
        let snapshot = ClipboardManager.snapshot()
        KeyEvents.sendCommandC()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { // allow time for copy to complete
            if let text = ClipboardManager.readPlainText() {
                let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown App"
                let clip = Clip(text: text, app: appName, createdAt: Date())
                QueueStore.shared.append(clip: clip)
                NSLog("[GigiCopyHelper] Captured: %@ from %@", text, appName)
                // Optional: show a small user notification in future
            }
            ClipboardManager.restore(snapshot: snapshot)
        }
    }

    @objc private func openDataFolder() {
        let fm = FileManager.default
        if let appSup = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let dir = appSup.appendingPathComponent("GigiCopyHelper", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(dir)
        }
    }
}

// MARK: - Accessibility
enum Accessibility {
    static func ensurePermissionPrompt() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

// MARK: - Key Events (simulate Cmd+C)
enum KeyEvents {
    static func sendCommandC() {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

// MARK: - Clipboard Manager
enum ClipboardManager {
    struct Snapshot {
        let items: [[String: Data]]
    }

    static func snapshot() -> Snapshot {
        let pb = NSPasteboard.general
        var itemsDump: [[String: Data]] = []
        for item in pb.pasteboardItems ?? [] {
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            itemsDump.append(dict)
        }
        return Snapshot(items: itemsDump)
    }

    static func restore(snapshot: Snapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let newItems: [NSPasteboardItem] = snapshot.items.map { dict in
            let item = NSPasteboardItem()
            for (rawType, data) in dict {
                let type = NSPasteboard.PasteboardType(rawType)
                item.setData(data, forType: type)
            }
            return item
        }
        pb.writeObjects(newItems)
    }

    static func readPlainText() -> String? {
        let pb = NSPasteboard.general
        if let s = pb.string(forType: .string) { return s }
        if let data = pb.data(forType: .rtf),
           let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return attr.string
        }
        return nil
    }
}

// MARK: - Global Hotkey Manager
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    struct Modifiers: OptionSet {
        let rawValue: UInt32
        static let cmd     = Modifiers(rawValue: UInt32(cmdKey))
        static let shift   = Modifiers(rawValue: UInt32(shiftKey))
        static let option  = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
    }

    // Non-capturing C callback; retrieves self from userData and calls stored handler
    private static let cCallback: EventHandlerUPP = { (next: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
        guard let userData = userData else { return noErr }
        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        manager.invokeHandler()
        return noErr
    }

    func register(keyCode: Int, modifiers: Modifiers, handler: @escaping () -> Void) {
        self.handler = handler

        let hotKeyID = EventHotKeyID(signature: OSType(0x47434748) /* 'GCGH' */, id: 1)
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        // Install a non-capturing event handler and pass self via userData
        InstallEventHandler(
            GetApplicationEventTarget(),
            HotKeyManager.cCallback,
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        RegisterEventHotKey(UInt32(keyCode), modifiers.rawValue, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    fileprivate func invokeHandler() {
        handler?()
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let eh = eventHandlerRef {
            RemoveEventHandler(eh)
        }
    }
}

// MARK: - Simple queue and model
struct Clip: Codable {
    let id: String
    let text: String
    let app: String
    let createdAt: Date

    init(text: String, app: String, createdAt: Date) {
        self.id = UUID().uuidString
        self.text = text
        self.app = app
        self.createdAt = createdAt
    }
}

final class QueueStore {
    static let shared = QueueStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.gigi.copyhelper.queuestore")

    private init() {
        let fm = FileManager.default
        let appSup = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = appSup.appendingPathComponent("GigiCopyHelper", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("queue.json", isDirectory: false)
        NSLog("[GigiCopyHelper] Queue file: \(fileURL.path)")
    }

    func append(clip: Clip) {
        queue.async {
            var items = self.load()
            items.append(clip)
            self.save(items)
        }
    }

    private func load() -> [Clip] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Clip].self, from: data)) ?? []
    }

    private func save(_ items: [Clip]) {
        let data = try? JSONEncoder().encode(items)
        try? data?.write(to: fileURL)
    }
}
