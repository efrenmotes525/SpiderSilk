#!/usr/bin/env bash
set -euo pipefail

# TopFlow-friendly wrapper around the HeadBridge installer.
# It can be downloaded alone via:
#   curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh -o /tmp/topflow-server.sh

REPO_RAW_BASE="${TOPFLOW_REPO_RAW_BASE:-https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_HEADBRIDGE_SCRIPT="${SCRIPT_DIR}/headbridge-server.sh"

export TOPFLOW_SERVICE_NAME="${TOPFLOW_SERVICE_NAME:-topflow-server}"
export TOPFLOW_INSTALL_DIR="${TOPFLOW_INSTALL_DIR:-/opt/topflow-server}"
export TOPFLOW_ETC_DIR="${TOPFLOW_ETC_DIR:-/etc/topflow-server}"

if [[ -f "$LOCAL_HEADBRIDGE_SCRIPT" ]]; then
  exec bash "$LOCAL_HEADBRIDGE_SCRIPT" "$@"
fi

TMP_SCRIPT="$(mktemp /tmp/headbridge-server.XXXXXX.sh)"
cleanup() {
  rm -f "$TMP_SCRIPT"
}
trap cleanup EXIT

curl -fsSL "https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/refs/heads/main/headbridge-server.sh" -o "$TMP_SCRIPT"
sed -i 's/\r$//' "$TMP_SCRIPT" 2>/dev/null || true
chmod +x "$TMP_SCRIPT"
exec bash "$TMP_SCRIPT" "$@"
