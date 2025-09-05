#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./install_host_manifest.sh [EXTENSION_ID] [APP_PATH]
# Example:
#   ./install_host_manifest.sh jbbojenedhccadjlbhbnjocncamghnik /Applications/GigiCopyHelper.app
# If APP_PATH is omitted, defaults to /Applications/GigiCopyHelper.app

EXT_ID="${1:-jbbojenedhccadjlbhbnjocncamghnik}"
APP_PATH="${2:-/Applications/GigiCopyHelper.app}"
HOST_BIN="$APP_PATH/Contents/MacOS/GigiCopyNMHost"
HOST_NAME="com.gigi.copytool"
DEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
MANIFEST_PATH="$DEST_DIR/$HOST_NAME.json"

if [[ ! -x "$HOST_BIN" ]]; then
  echo "[ERROR] Native host binary not found at: $HOST_BIN"
  echo "- Build the GigiCopyNMHost target and embed it into the app bundle"
  echo "- Or pass the app path explicitly as the 2nd argument"
  exit 1
fi

mkdir -p "$DEST_DIR"

cat > "$MANIFEST_PATH" <<JSON
{
  "name": "$HOST_NAME",
  "description": "Gigi’s Copy Tool Native Host",
  "path": "$HOST_BIN",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXT_ID/"
  ]
}
JSON

echo "[OK] Wrote manifest: $MANIFEST_PATH"
echo "[OK] Points to host:  $HOST_BIN"
echo "[HINT] Restart Chrome so it reloads native messaging hosts."
