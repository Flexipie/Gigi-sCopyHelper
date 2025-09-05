# GigiCopyHelper (macOS Menubar Clipboard Helper)

GigiCopyHelper is a macOS menubar app that lets you capture text from any native app with a global shortcut and exposes those clips to a Chrome extension via Native Messaging.

- Global shortcut: Command+Shift+U (configurable in source)
- Captures from native apps (e.g., Preview, PDF viewers, IDEs)
- Stores clips in a persistent queue (`queue.json`)
- Chrome extension drains the queue and merges clips into its overlay UI

## Requirements

- macOS 13+ (Ventura) recommended
- Xcode 15+
- Google Chrome (Stable)

## Features

- Menubar-only app (agent) with status icon and menu
  - Capture Selection (⌘⇧U)
  - Open Data Folder
  - Quit
- Accessibility permission prompt on first run (for simulating Cmd+C)
- Carbon global hotkey registration (Cmd+Shift+U)
- Clipboard snapshot/restore safety
- Persistent queue: `queue.json`
  - Sandboxed path (default):
    `~/Library/Containers/Flexipie.GigiCopyHelper/Data/Library/Application Support/GigiCopyHelper/queue.json`
  - Non-sandbox path (if you disable App Sandbox):
    `~/Library/Application Support/GigiCopyHelper/queue.json`
- Native Messaging Host (CLI) packaged in app bundle
- Install script for host manifest

## Build & Run (Helper app)

1. Open the Xcode project `GigiCopyHelper.xcodeproj`.
2. Ensure App Sandbox is enabled (recommended), and Hardened Runtime for development is allowed.
3. Scheme: `GigiCopyHelper` → Product → Build (Cmd+B).
4. Run the app (or open the built app) and grant Accessibility permission when prompted.

## Embed the Native Messaging Host

1. Scheme: `GigiCopyNMHost` → Build (Cmd+B).
2. Select target `GigiCopyHelper` → Build Phases → add a **Copy Files** phase (if not already present):
   - Destination: `Executables`
   - Name: `Embed NM Host`
   - Add product `GigiCopyNMHost` to this phase
3. Scheme: `GigiCopyHelper` → Build (Cmd+B).
4. Copy the built app to `/Applications` and replace if prompted.
   - Verify the host exists at:
     `/Applications/GigiCopyHelper.app/Contents/MacOS/GigiCopyNMHost`

## Install the Chrome Native Messaging Host Manifest

1. Find your extension ID in Chrome: `chrome://extensions` (Developer Mode → copy the ID of Gigi’s Copy Tool).
2. Run the install script with your ID and the app path:

```bash
cd "/Users/yourname/path/to/GigiCopyHelper/Scripts"
chmod +x install_host_manifest.sh
./install_host_manifest.sh <YOUR_EXTENSION_ID> "/Applications/GigiCopyHelper.app"
```

This writes the manifest to:
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.gigi.copytool.json`.

3. Fully quit and reopen Chrome so it reloads native hosts.

## Chrome Extension Integration

- The extension needs the following in `manifest.json`:
  - `"permissions": ["nativeMessaging", "alarms", ...]`
- The background service worker connects to `com.gigi.copytool` every ~5 seconds and sends `{type: 'drain'}`. Incoming `{type: 'clip'}` messages are merged into storage and routed to the current folder.
- Shortcuts in Chrome are user-configurable at `chrome://extensions/shortcuts`.

## Usage

- Select text in any macOS app and press ⌘⇧U.
- The helper simulates Cmd+C, reads text from the clipboard, restores the original clipboard, and appends to `queue.json`.
- The Chrome extension drains the queue and shows imported clips in the overlay.

## Troubleshooting

- "Access to the specified native messaging host is forbidden"
  - Ensure the manifest `allowed_origins` matches your exact extension ID.
  - Restart Chrome after changing the manifest.

- "Error when communicating with the native messaging host"
  - Ensure the app in `/Applications` contains the latest `GigiCopyNMHost` binary (rebuild and copy again).
  - The host must only write framed JSON to stdout. No other prints.

- Service Worker logs
  - Open `chrome://extensions` → your extension → Service Worker → Inspect. The background logs host connect/disconnect and drain results.

- Manual host test (bypass Chrome):

```bash
python3 - <<'PY'
import sys, struct, json, subprocess
host = "/Applications/GigiCopyHelper.app/Contents/MacOS/GigiCopyNMHost"
p = subprocess.Popen([host], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
msg = json.dumps({"type":"drain"}).encode("utf-8")
p.stdin.write(struct.pack("<I", len(msg))); p.stdin.write(msg); p.stdin.flush()
def read_msg(f):
    hdr = f.read(4)
    if not hdr: return None
    (length,) = struct.unpack("<I", hdr)
    payload = f.read(length)
    print(payload.decode("utf-8"))
    return True
while read_msg(p.stdout): pass
PY
```

## Development Notes

- Change the hotkey in `AppDelegate.swift` (Carbon key code and menu label).
- Queue schema is a JSON array of `{ id, text, app, createdAt }`.
- The host reads the sandboxed queue path by default.

## License

MIT (add a LICENSE file if you plan to publish under MIT or another license)

## Release Notes (v0.1.0)

- Initial release with:
  - Menubar helper app (⌘⇧U capture)
  - Accessibility permission prompt
  - Clipboard snapshot/restore
  - Persistent queue storage
  - Native Messaging host + install script
  - Chrome extension integration
