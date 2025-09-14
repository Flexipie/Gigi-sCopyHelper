#!/usr/bin/env bash
set -euo pipefail

# Install the Native Messaging host manifest for GigiCopyHelper.
#
# Default behavior (no args):
#   - Uses the Chrome Web Store extension ID
#   - Auto-detects GigiCopyHelper.app in /Applications or ~/Applications
#   - Installs manifests for Chrome Stable, Chrome Canary, Brave, and Edge
#
# Usage:
#   ./install_host_manifest.sh [--browser chrome|canary|brave|edge|all] [--ext-id EXT_ID] [--app APP_PATH]
# Examples:
#   ./install_host_manifest.sh                       # auto everything
#   ./install_host_manifest.sh --browser brave       # brave only
#   ./install_host_manifest.sh --ext-id abcdef...    # custom extension id
#   ./install_host_manifest.sh --app "/Applications/GigiCopyHelper.app"

HOST_NAME="com.gigi.copytool"

# Stable Chrome Web Store ID for Gigi's Copy Tool (replace if changed)
EXT_ID_DEFAULT="kloniobkbogcldkemcbleomoecphcpnm"

BROWSER="all"
EXT_ID="$EXT_ID_DEFAULT"
APP_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --browser)
      BROWSER="${2:-all}"; shift 2;;
    --ext-id)
      EXT_ID="${2}"; shift 2;;
    --app)
      APP_PATH="${2}"; shift 2;;
    *)
      echo "Unknown arg: $1"; exit 1;;
  esac
done

# Auto-detect app path if not provided
detect_app() {
  local candidate
  for candidate in \
    "/Applications/GigiCopyHelper.app" \
    "$HOME/Applications/GigiCopyHelper.app"; do
    if [[ -d "$candidate" ]]; then
      echo "$candidate"; return 0
    fi
  done
  # Try mdfind by bundle id
  if command -v mdfind >/dev/null 2>&1; then
    candidate="$(mdfind "kMDItemCFBundleIdentifier == 'Flexipie.GigiCopyHelper'" | head -n1 || true)"
    if [[ -n "${candidate}" && -d "${candidate}" ]]; then
      echo "$candidate"; return 0
    fi
  fi
  return 1
}

if [[ -z "$APP_PATH" ]]; then
  if ! APP_PATH="$(detect_app)"; then
    echo "[ERROR] Could not locate GigiCopyHelper.app. Please install it to /Applications or pass --app path."
    exit 1
  fi
fi

HOST_BIN="$APP_PATH/Contents/MacOS/GigiCopyNMHost"
if [[ ! -x "$HOST_BIN" ]]; then
  echo "[ERROR] Native host binary not found at: $HOST_BIN"
  echo "- Ensure the app bundle contains GigiCopyNMHost (Embed NM Host build phase)"
  echo "- Or pass the app path explicitly via --app"
  exit 1
fi

declare -A TARGET_DIRS
TARGET_DIRS[chrome]="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
TARGET_DIRS[canary]="$HOME/Library/Application Support/Google/Chrome Canary/NativeMessagingHosts"
TARGET_DIRS[brave]="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
TARGET_DIRS[edge]="$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"

write_manifest() {
  local dest_dir="$1"
  mkdir -p "$dest_dir"
  local manifest_path="$dest_dir/$HOST_NAME.json"
  cat > "$manifest_path" <<JSON
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
  echo "[OK] Wrote: $manifest_path"
}

case "$BROWSER" in
  all)
    for key in chrome canary brave edge; do
      write_manifest "${TARGET_DIRS[$key]}"
    done
    ;;
  chrome|canary|brave|edge)
    write_manifest "${TARGET_DIRS[$BROWSER]}"
    ;;
  *)
    echo "[ERROR] Unknown browser: $BROWSER"; exit 1;;
esac

echo "[OK] Host: $HOST_BIN"
echo "[OK] Extension ID: $EXT_ID"
echo "[NEXT] Fully quit and reopen your browser so it reloads native hosts. Then reload the extension."
