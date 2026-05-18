#!/bin/sh
set -eu

APP_NAME="headbridge-server"
DISPLAY_NAME="HeadBridge"
DEFAULT_SERVICE_NAME="headbridge-server"
DEFAULT_INSTALL_DIR="/opt/headbridge-server"
DEFAULT_ETC_DIR="/etc/headbridge-server"
DEFAULT_LISTEN="0.0.0.0:6379"
DEFAULT_MAX_CONNECTIONS="10000"
DEFAULT_MAX_CONNECTIONS_PER_IP="256"
DEFAULT_FORWARDING_CONFIG="topflow-forwarding.json"
DEFAULT_DOWNLOAD_URL="https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/refs/heads/main/headbridge-server-alpine-x86_64"
LOCAL_BINARY_NAME="headbridge-server-alpine-x86_64"
ALPINE_DEPENDENCIES="ca-certificates curl openssl openrc libcap python3"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

SERVICE_NAME="${HEADBRIDGE_SERVICE_NAME:-$DEFAULT_SERVICE_NAME}"
INSTALL_DIR="${HEADBRIDGE_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
ETC_DIR="${HEADBRIDGE_ETC_DIR:-$DEFAULT_ETC_DIR}"
HEADBRIDGE_USER="${HEADBRIDGE_USER:-headbridge}"
HEADBRIDGE_GROUP="${HEADBRIDGE_GROUP:-headbridge}"

HEADBRIDGE_LISTEN="${HEADBRIDGE_LISTEN:-$DEFAULT_LISTEN}"
HEADBRIDGE_PUBLIC_ENDPOINT="${HEADBRIDGE_PUBLIC_ENDPOINT:-}"
HEADBRIDGE_NODE_NAME="${HEADBRIDGE_NODE_NAME:-TopFlow}"
HEADBRIDGE_GROUP_NAME="${HEADBRIDGE_GROUP_NAME:-AutoDeploy}"
HEADBRIDGE_SNI="${HEADBRIDGE_SNI:-www.cloudflare.com}"
HEADBRIDGE_PSK="${HEADBRIDGE_PSK:-}"
HEADBRIDGE_MAX_CONNECTIONS="${HEADBRIDGE_MAX_CONNECTIONS:-$DEFAULT_MAX_CONNECTIONS}"
HEADBRIDGE_MAX_CONNECTIONS_PER_IP="${HEADBRIDGE_MAX_CONNECTIONS_PER_IP:-$DEFAULT_MAX_CONNECTIONS_PER_IP}"
HEADBRIDGE_VVIP_RELAY_LISTEN="${HEADBRIDGE_VVIP_RELAY_LISTEN:-off}"
HEADBRIDGE_SKIP_CERT_VERIFY="${HEADBRIDGE_SKIP_CERT_VERIFY:-true}"
HEADBRIDGE_DEBUG="${HEADBRIDGE_DEBUG:-false}"
HEADBRIDGE_CA_CERT="${HEADBRIDGE_CA_CERT:-}"
HEADBRIDGE_CA_KEY="${HEADBRIDGE_CA_KEY:-}"
HEADBRIDGE_GENERATE_CA="${HEADBRIDGE_GENERATE_CA:-false}"
HEADBRIDGE_EXTRA_ARGS="${HEADBRIDGE_EXTRA_ARGS:-}"
HEADBRIDGE_ADMIN_TOKEN="${HEADBRIDGE_ADMIN_TOKEN:-}"
HEADBRIDGE_FORWARDING_CONFIG="${HEADBRIDGE_FORWARDING_CONFIG:-$DEFAULT_FORWARDING_CONFIG}"
HEADBRIDGE_VIDEO_HONEYPOT="${HEADBRIDGE_VIDEO_HONEYPOT:-true}"
HEADBRIDGE_BINARY_PATH="${HEADBRIDGE_BINARY_PATH:-}"
HEADBRIDGE_DOWNLOAD_URL="${HEADBRIDGE_DOWNLOAD_URL:-$DEFAULT_DOWNLOAD_URL}"

KEEP_CONFIG="${KEEP_CONFIG:-false}"
REMOVE_USER="${REMOVE_USER:-true}"
ASSUME_YES="${ASSUME_YES:-false}"
DETECTED_PUBLIC_IPV4="${DETECTED_PUBLIC_IPV4:-}"
DETECTED_PUBLIC_IPV6="${DETECTED_PUBLIC_IPV6:-}"
DETECTED_PUBLIC_IPS_READY="${DETECTED_PUBLIC_IPS_READY:-false}"

refresh_paths() {
  BIN_PATH="${INSTALL_DIR}/${APP_NAME}"
  RUNNER_PATH="${INSTALL_DIR}/run-headbridge-server.sh"
  ENV_FILE="${ETC_DIR}/headbridge-server.env"
  OPENRC_SERVICE="/etc/init.d/${SERVICE_NAME}"
  PID_DIR="/run/${SERVICE_NAME}"
  PID_FILE="${PID_DIR}/${SERVICE_NAME}.pid"
}

refresh_paths

log() {
  printf '[%s] %s\n' "$DISPLAY_NAME" "$*"
}

log_stderr() {
  printf '[%s] %s\n' "$DISPLAY_NAME" "$*" >&2
}

warn() {
  printf '[%s] %s\n' "$DISPLAY_NAME" "$*" >&2
}

die() {
  printf '[%s] %s\n' "$DISPLAY_NAME" "$*" >&2
  exit 1
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_true() {
  case "$(lower "${1:-false}")" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

escape_single_quotes() {
  printf "%s" "$1" | sed "s/'/'\"'\"'/g"
}

normalize_host() {
  local_host="${1:-}"
  local_host=${local_host#[}
  local_host=${local_host%]}
  printf '%s' "$local_host"
}

parse_host_port() {
  value="${1:-}"
  default_port="${2:-}"
  case "$value" in
    \[*\]:*)
      host=$(printf '%s' "$value" | sed -n 's/^\[\(.*\)\]:\([^:]*\)$/\1/p')
      port=$(printf '%s' "$value" | sed -n 's/^\[\(.*\)\]:\([^:]*\)$/\2/p')
      ;;
    *:*)
      host=${value%:*}
      port=${value##*:}
      ;;
    *)
      host=$value
      port=$default_port
      ;;
  esac
  PARSED_HOST=$(normalize_host "$host")
  PARSED_PORT="$port"
}

format_endpoint() {
  host=$(normalize_host "$1")
  port="$2"
  case "$host" in
    *:*) printf '[%s]:%s' "$host" "$port" ;;
    *) printf '%s:%s' "$host" "$port" ;;
  esac
}

is_wildcard_host() {
  host=$(normalize_host "$1")
  [ "$host" = "0.0.0.0" ] || [ "$host" = "::" ]
}

trim_value() {
  value="${1:-}"
  printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

is_public_ipv4() {
  ip="${1:-}"
  printf '%s\n' "$ip" | awk -F. '
    NF != 4 { exit 1 }
    {
      for (i = 1; i <= 4; i++) {
        if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) exit 1
      }
      a = $1 + 0
      b = $2 + 0
      c = $3 + 0
      if (a == 0 || a == 10 || a == 127 || a >= 224) exit 1
      if (a == 100 && b >= 64 && b <= 127) exit 1
      if (a == 169 && b == 254) exit 1
      if (a == 172 && b >= 16 && b <= 31) exit 1
      if (a == 192 && b == 0 && (c == 0 || c == 2)) exit 1
      if (a == 192 && b == 168) exit 1
      if (a == 198 && (b == 18 || b == 19)) exit 1
      if (a == 198 && b == 51 && c == 100) exit 1
      if (a == 203 && b == 0 && c == 113) exit 1
      exit 0
    }
  ' >/dev/null 2>&1
}

is_public_ipv6() {
  ip=$(normalize_host "${1:-}")
  [ -n "$ip" ] || return 1
  case "$ip" in
    *:*) ;;
    *) return 1 ;;
  esac
  lower_ip=$(lower "$ip")
  case "$lower_ip" in
    ::|::1|fc*|fd*|fe8*|fe9*|fea*|feb*|2001:db8*) return 1 ;;
  esac
  return 0
}

detect_public_ipv4_from_web() {
  for url in \
    "https://api.ipify.org" \
    "https://ipv4.icanhazip.com" \
    "https://ifconfig.me/ip"
  do
    ip=$(curl -4 -fsS --max-time 5 "$url" 2>/dev/null | tr -d '\r\n' || true)
    if is_public_ipv4 "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
  done
}

detect_public_ipv6_from_web() {
  for url in \
    "https://api64.ipify.org" \
    "https://ipv6.icanhazip.com"
  do
    ip=$(curl -6 -fsS --max-time 5 "$url" 2>/dev/null | tr -d '\r\n' || true)
    if is_public_ipv6 "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
  done
}

cache_public_ips() {
  is_true "$DETECTED_PUBLIC_IPS_READY" && return 0
  DETECTED_PUBLIC_IPV4=$(detect_public_ipv4_from_web || true)
  if ! is_public_ipv4 "$DETECTED_PUBLIC_IPV4"; then
    DETECTED_PUBLIC_IPV4=""
  fi
  DETECTED_PUBLIC_IPV6=$(detect_public_ipv6_from_web || true)
  if ! is_public_ipv6 "$DETECTED_PUBLIC_IPV6"; then
    DETECTED_PUBLIC_IPV6=""
  fi
  DETECTED_PUBLIC_IPS_READY="true"
}

detect_public_ipv4() {
  cache_public_ips
  printf '%s' "$DETECTED_PUBLIC_IPV4"
}

detect_public_ipv6() {
  cache_public_ips
  printf '%s' "$DETECTED_PUBLIC_IPV6"
}

resolve_vvip_relay_listen() {
  listen_value="$1"
  relay_value="${2:-off}"
  case "$(lower "$relay_value")" in
    0|false|no|off) return 0 ;;
    auto)
      parse_host_port "$listen_value" ""
      if [ -n "${PARSED_PORT:-}" ] && [ "${PARSED_PORT}" -ge 1 ] 2>/dev/null && [ "${PARSED_PORT}" -lt 65535 ] 2>/dev/null; then
        format_endpoint "${PARSED_HOST}" "$((PARSED_PORT + 1))"
      fi
      ;;
    *) printf '%s' "$relay_value" ;;
  esac
}

listen_port_requires_privileged_bind() {
  parse_host_port "$HEADBRIDGE_LISTEN" ""
  if [ -n "${PARSED_PORT:-}" ] && [ "${PARSED_PORT}" -lt 1024 ] 2>/dev/null; then
    return 0
  fi
  relay_listen=$(resolve_vvip_relay_listen "$HEADBRIDGE_LISTEN" "$HEADBRIDGE_VVIP_RELAY_LISTEN" || true)
  if [ -n "$relay_listen" ]; then
    parse_host_port "$relay_listen" ""
    if [ -n "${PARSED_PORT:-}" ] && [ "${PARSED_PORT}" -lt 1024 ] 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "run this script as root"
  fi
}

ensure_openrc() {
  command -v rc-update >/dev/null 2>&1 || die "rc-update is required"
  command -v rc-service >/dev/null 2>&1 || die "rc-service is required"
  command -v start-stop-daemon >/dev/null 2>&1 || die "start-stop-daemon is required"
}

usage() {
  cat <<'EOF'
HeadBridge Alpine/OpenRC installer

Usage:
  sh headbridge-server-alpine-openrc.sh install   [options]
  sh headbridge-server-alpine-openrc.sh update    [options]
  sh headbridge-server-alpine-openrc.sh uninstall [options]

Commands:
  install     install binary, env file, and OpenRC service
  update      replace binary and restart the OpenRC service
  uninstall   remove the OpenRC service and installed files

Install options:
  --psk <Base64>                 32-byte PSK in Base64; auto-generated if omitted
  --listen <host:port>           default: 0.0.0.0:6379
  --public-endpoint <host:port[,host:port]>
                                 client-facing public endpoint; auto-detected when omitted
  --node-name <name>             client node name, default: TopFlow
  --group-name <name>            client group name, default: AutoDeploy
  --sni <host>                   client SNI, default: www.cloudflare.com
  --vvip-relay-listen <auto|off|host:port>
                                 default: off; auto means main port + 1, e.g. 6379 -> 6380
  --max-connections <num>        default: 10000
  --max-connections-per-ip <num> default: 256
  --binary-path <path>           use a local binary instead of downloading
  --download-url <url>           fallback download URL when no local binary is present; GitHub blob URLs are converted to raw URLs
  --ca-cert <path>               optional root CA certificate path
  --ca-key <path>                optional root CA private key path
  --generate-ca                  generate CA files at startup
  --admin-token <token>          admin control plane token; auto-generated if omitted
  --forwarding-config <path>     default: topflow-forwarding.json
  --debug                        enable debug logs
  --skip-cert-verify             keep compatibility with current server CLI
  --no-video-honeypot            disable fake camera honeypot responses
  --user <name>                  service user, default: headbridge
  --group <name>                 service group, default: headbridge
  --service-name <name>          OpenRC service name, default: headbridge-server
  --install-dir <dir>            default: /opt/headbridge-server
  --etc-dir <dir>                default: /etc/headbridge-server
  --extra-args "<args>"          appended to the server command line

Update options:
  --binary-path <path>           replace with a local binary
  --download-url <url>           replace from a remote URL
  --public-endpoint <host:port[,host:port]>
  --node-name <name>
  --group-name <name>
  --sni <host>
  --service-name <name>
  --install-dir <dir>
  --etc-dir <dir>

Uninstall options:
  --yes                          do not prompt for confirmation
  --keep-config                  keep the config directory
  --keep-user                    keep the runtime user and group
  --service-name <name>
  --install-dir <dir>
  --etc-dir <dir>

Default local binary lookup:
  1. ./headbridge-server-alpine-x86_64
  2. ./headbridge-server
  3. download from the default Alpine URL:
     https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/refs/heads/main/headbridge-server-alpine-x86_64

Alpine dependencies installed by this script:
  ca-certificates  TLS trust store for HTTPS downloads
  curl             download the Alpine server binary
  openssl          generate and validate PSK/admin token
  openrc           rc-service, rc-update, checkpath, start-stop-daemon
  libcap           setcap for privileged ports when needed
  python3          generate TopFlow share links
EOF
}

parse_install_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --psk) HEADBRIDGE_PSK="$2"; shift 2 ;;
      --listen) HEADBRIDGE_LISTEN="$2"; shift 2 ;;
      --public-endpoint) HEADBRIDGE_PUBLIC_ENDPOINT="$2"; shift 2 ;;
      --node-name) HEADBRIDGE_NODE_NAME="$2"; shift 2 ;;
      --group-name) HEADBRIDGE_GROUP_NAME="$2"; shift 2 ;;
      --sni) HEADBRIDGE_SNI="$2"; shift 2 ;;
      --vvip-relay-listen) HEADBRIDGE_VVIP_RELAY_LISTEN="$2"; shift 2 ;;
      --max-connections) HEADBRIDGE_MAX_CONNECTIONS="$2"; shift 2 ;;
      --max-connections-per-ip) HEADBRIDGE_MAX_CONNECTIONS_PER_IP="$2"; shift 2 ;;
      --binary-path) HEADBRIDGE_BINARY_PATH="$2"; shift 2 ;;
      --download-url) HEADBRIDGE_DOWNLOAD_URL="$2"; shift 2 ;;
      --ca-cert) HEADBRIDGE_CA_CERT="$2"; shift 2 ;;
      --ca-key) HEADBRIDGE_CA_KEY="$2"; shift 2 ;;
      --generate-ca) HEADBRIDGE_GENERATE_CA="true"; shift ;;
      --admin-token) HEADBRIDGE_ADMIN_TOKEN="$2"; shift 2 ;;
      --forwarding-config) HEADBRIDGE_FORWARDING_CONFIG="$2"; shift 2 ;;
      --debug|-d) HEADBRIDGE_DEBUG="true"; shift ;;
      --skip-cert-verify) HEADBRIDGE_SKIP_CERT_VERIFY="true"; shift ;;
      --no-video-honeypot) HEADBRIDGE_VIDEO_HONEYPOT="false"; shift ;;
      --user) HEADBRIDGE_USER="$2"; shift 2 ;;
      --group) HEADBRIDGE_GROUP="$2"; shift 2 ;;
      --service-name) SERVICE_NAME="$2"; shift 2 ;;
      --install-dir) INSTALL_DIR="$2"; shift 2 ;;
      --etc-dir) ETC_DIR="$2"; shift 2 ;;
      --extra-args) HEADBRIDGE_EXTRA_ARGS="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown install option: $1" ;;
    esac
  done
  refresh_paths
}

parse_update_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --binary-path) HEADBRIDGE_BINARY_PATH="$2"; shift 2 ;;
      --download-url) HEADBRIDGE_DOWNLOAD_URL="$2"; shift 2 ;;
      --public-endpoint) HEADBRIDGE_PUBLIC_ENDPOINT="$2"; shift 2 ;;
      --node-name) HEADBRIDGE_NODE_NAME="$2"; shift 2 ;;
      --group-name) HEADBRIDGE_GROUP_NAME="$2"; shift 2 ;;
      --sni) HEADBRIDGE_SNI="$2"; shift 2 ;;
      --service-name) SERVICE_NAME="$2"; shift 2 ;;
      --install-dir) INSTALL_DIR="$2"; shift 2 ;;
      --etc-dir) ETC_DIR="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown update option: $1" ;;
    esac
  done
  refresh_paths
}

parse_uninstall_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --yes) ASSUME_YES="true"; shift ;;
      --keep-config) KEEP_CONFIG="true"; shift ;;
      --keep-user) REMOVE_USER="false"; shift ;;
      --service-name) SERVICE_NAME="$2"; shift 2 ;;
      --install-dir) INSTALL_DIR="$2"; shift 2 ;;
      --etc-dir) ETC_DIR="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown uninstall option: $1" ;;
    esac
  done
  refresh_paths
}

install_dependencies() {
  command -v apk >/dev/null 2>&1 || die "apk is required; run this installer on Alpine Linux"
  log "installing Alpine dependencies: ${ALPINE_DEPENDENCIES}"
  apk add --no-cache ${ALPINE_DEPENDENCIES}
  update-ca-certificates >/dev/null 2>&1 || true
}

ensure_runtime_user() {
  if ! grep -q "^${HEADBRIDGE_GROUP}:" /etc/group 2>/dev/null; then
    addgroup -S "$HEADBRIDGE_GROUP" >/dev/null
  fi

  if ! grep -q "^${HEADBRIDGE_USER}:" /etc/passwd 2>/dev/null; then
    adduser -S -D -H -h "$INSTALL_DIR" -s /sbin/nologin -G "$HEADBRIDGE_GROUP" "$HEADBRIDGE_USER" >/dev/null
  fi
}

generate_or_validate_psk() {
  if [ -z "$HEADBRIDGE_PSK" ]; then
    HEADBRIDGE_PSK=$(openssl rand -base64 32 | tr -d '\r\n')
    log "generated a new PSK"
  fi

  decoded_len=$(printf '%s' "$HEADBRIDGE_PSK" | openssl base64 -d -A 2>/dev/null | wc -c | tr -d ' ')
  [ "$decoded_len" = "32" ] || die "PSK must decode to exactly 32 bytes"
}

generate_or_validate_admin_token() {
  if [ -z "$HEADBRIDGE_ADMIN_TOKEN" ]; then
    HEADBRIDGE_ADMIN_TOKEN=$(openssl rand -base64 32 | tr -d '\r\n')
    log "generated a new admin token"
  fi

  [ ${#HEADBRIDGE_ADMIN_TOKEN} -ge 16 ] || die "admin token must be at least 16 characters"
}

load_env_if_exists() {
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
  fi
}

normalize_download_url() {
  url="$1"
  case "$url" in
    https://github.com/*/*/blob/*)
      rest=${url#https://github.com/}
      owner=${rest%%/*}
      rest=${rest#*/}
      repo=${rest%%/*}
      rest=${rest#*/blob/}
      branch=${rest%%/*}
      path=${rest#*/}
      printf 'https://raw.githubusercontent.com/%s/%s/refs/heads/%s/%s' "$owner" "$repo" "$branch" "$path"
      ;;
    *)
      printf '%s' "$url"
      ;;
  esac
}

resolve_source_binary() {
  if [ -n "$HEADBRIDGE_BINARY_PATH" ]; then
    printf '%s' "$HEADBRIDGE_BINARY_PATH"
    return 0
  fi
  if [ -f "${SCRIPT_DIR}/${LOCAL_BINARY_NAME}" ]; then
    printf '%s' "${SCRIPT_DIR}/${LOCAL_BINARY_NAME}"
    return 0
  fi
  if [ -f "${SCRIPT_DIR}/${APP_NAME}" ]; then
    printf '%s' "${SCRIPT_DIR}/${APP_NAME}"
    return 0
  fi
  normalize_download_url "$HEADBRIDGE_DOWNLOAD_URL"
}

copy_or_download_binary() {
  source_ref=$(resolve_source_binary)
  tmp_file=$(mktemp)
  case "$source_ref" in
    http://*|https://*)
      log_stderr "downloading Alpine binary from $source_ref"
      curl -fsSL "$source_ref" -o "$tmp_file"
      ;;
    *)
      [ -f "$source_ref" ] || die "binary not found: $source_ref"
      log_stderr "using local binary $source_ref"
      cp "$source_ref" "$tmp_file"
      ;;
  esac

  if head -c 4 "$tmp_file" | od -An -t x1 | tr -d ' \n' | grep -qi '^7f454c46$'; then
    :
  else
    rm -f "$tmp_file"
    die "the downloaded payload is not an ELF executable; use the raw Alpine binary URL, not a GitHub HTML blob page"
  fi

  chmod 0755 "$tmp_file"
  printf '%s' "$tmp_file"
}

install_binary() {
  mkdir -p "$INSTALL_DIR" "$ETC_DIR"
  tmp_file=$(copy_or_download_binary)
  mv "$tmp_file" "$BIN_PATH"
  chmod 0755 "$BIN_PATH"
  chown root:root "$BIN_PATH"
}

configure_bind_capability() {
  if command -v setcap >/dev/null 2>&1; then
    if listen_port_requires_privileged_bind; then
      setcap 'cap_net_bind_service=+ep' "$BIN_PATH" || warn "failed to grant cap_net_bind_service"
    else
      setcap -r "$BIN_PATH" >/dev/null 2>&1 || true
    fi
  fi
}

normalize_public_endpoints() {
  value="$1"
  default_port="$2"
  printf '%s' "$value" | tr ';' ',' | tr ',' '\n' | while IFS= read -r item; do
    item=$(trim_value "$item")
    [ -n "$item" ] || continue
    parse_host_port "$item" "$default_port"
    format_endpoint "$PARSED_HOST" "$PARSED_PORT"
    printf '\n'
  done
}

detect_public_endpoints() {
  parse_host_port "$HEADBRIDGE_LISTEN" ""
  listen_host="$PARSED_HOST"
  listen_port="$PARSED_PORT"

  if [ -n "${HEADBRIDGE_PUBLIC_ENDPOINT:-}" ]; then
    normalize_public_endpoints "$HEADBRIDGE_PUBLIC_ENDPOINT" "$listen_port"
    return 0
  fi

  if ! is_wildcard_host "$listen_host"; then
    format_endpoint "$listen_host" "$listen_port"
    printf '\n'
    return 0
  fi

  emitted="false"
  if [ "$listen_host" = "::" ]; then
    public_v4=$(detect_public_ipv4)
    public_v6=$(detect_public_ipv6)
    if [ -n "$public_v4" ]; then
      format_endpoint "$public_v4" "$listen_port"
      printf '\n'
      emitted="true"
    fi
    if [ -n "$public_v6" ]; then
      format_endpoint "$public_v6" "$listen_port"
      printf '\n'
      emitted="true"
    fi
    is_true "$emitted" && return 0
  else
    public_v4=$(detect_public_ipv4)
    if [ -n "$public_v4" ]; then
      format_endpoint "$public_v4" "$listen_port"
      printf '\n'
      return 0
    fi
  fi

  format_endpoint "REPLACE_WITH_PUBLIC_HOST" "$listen_port"
  printf '\n'
}

build_topflow_share_json() {
  endpoints="$1"
  if is_true "$HEADBRIDGE_SKIP_CERT_VERIFY"; then
    insecure_tls="true"
  else
    insecure_tls="false"
  fi

  relay_listen=$(resolve_vvip_relay_listen "$HEADBRIDGE_LISTEN" "$HEADBRIDGE_VVIP_RELAY_LISTEN" || true)
  if [ -n "$relay_listen" ]; then
    parse_host_port "$relay_listen" ""
    relay_port="$PARSED_PORT"
    vvip_enabled="true"
  else
    relay_port=""
    vvip_enabled="false"
  fi

  HEADBRIDGE_SHARE_ENDPOINTS="$endpoints" \
  HEADBRIDGE_SHARE_NODE_NAME="$HEADBRIDGE_NODE_NAME" \
  HEADBRIDGE_SHARE_GROUP_NAME="$HEADBRIDGE_GROUP_NAME" \
  HEADBRIDGE_SHARE_SNI="$HEADBRIDGE_SNI" \
  HEADBRIDGE_SHARE_PSK="$HEADBRIDGE_PSK" \
  HEADBRIDGE_SHARE_ADMIN_TOKEN="$HEADBRIDGE_ADMIN_TOKEN" \
  HEADBRIDGE_SHARE_INSECURE_TLS="$insecure_tls" \
  HEADBRIDGE_SHARE_VVIP_ENABLED="$vvip_enabled" \
  HEADBRIDGE_SHARE_VVIP_RELAY_PORT="$relay_port" \
  python3 <<'PY'
import json
import os
import uuid

endpoints = [line.strip() for line in os.environ["HEADBRIDGE_SHARE_ENDPOINTS"].splitlines() if line.strip()]
node_name = os.environ["HEADBRIDGE_SHARE_NODE_NAME"]
group_name = os.environ["HEADBRIDGE_SHARE_GROUP_NAME"]
sni = os.environ["HEADBRIDGE_SHARE_SNI"]
psk = os.environ["HEADBRIDGE_SHARE_PSK"]
admin_token = os.environ.get("HEADBRIDGE_SHARE_ADMIN_TOKEN", "").strip()
insecure_tls = os.environ["HEADBRIDGE_SHARE_INSECURE_TLS"].lower() == "true"
vvip_enabled = os.environ["HEADBRIDGE_SHARE_VVIP_ENABLED"].lower() == "true"
vvip_relay_port = os.environ.get("HEADBRIDGE_SHARE_VVIP_RELAY_PORT", "").strip()

def parse_endpoint(endpoint):
    if endpoint.startswith("["):
        end = endpoint.find("]")
        if end <= 0:
            raise ValueError(f"invalid IPv6 endpoint: {endpoint}")
        host = endpoint[1:end]
        rest = endpoint[end + 1:]
        port = int(rest[1:]) if rest.startswith(":") else 0
        return host, port
    host, sep, port_text = endpoint.rpartition(":")
    if not sep:
        raise ValueError(f"endpoint missing port: {endpoint}")
    return host, int(port_text)

def endpoint_family(host):
    if ":" in host:
        return "IPv6"
    parts = host.split(".")
    if len(parts) == 4 and all(part.isdigit() and 0 <= int(part) <= 255 for part in parts):
        return "IPv4"
    return "Domain"

nodes = []
for endpoint in endpoints:
    host, port = parse_endpoint(endpoint)
    family = endpoint_family(host)
    display_name = node_name if len(endpoints) == 1 else f"{node_name} {family}"
    node = {
        "id": str(uuid.uuid4()),
        "name": display_name,
        "host": host,
        "group": group_name,
        "port": port,
        "sni": sni,
        "insecureTls": insecure_tls,
        "pskB64": psk,
        "kernelType": "HeadBridge"
    }
    if admin_token:
        node["adminToken"] = admin_token
    if vvip_enabled:
        node["vvipEnabled"] = True
        if vvip_relay_port:
            node["vvipRelayPort"] = int(vvip_relay_port)
    nodes.append(node)

share = {
    "app": "TopFlow",
    "format": "topflow-share",
    "formatVersion": 1,
    "activeIndex": 0,
    "nodes": nodes
}

print(json.dumps(share, ensure_ascii=False, separators=(",", ":")))
PY
}

build_topflow_link() {
  endpoints="$1"
  share_json=$(build_topflow_share_json "$endpoints")
  HEADBRIDGE_SHARE_JSON="$share_json" python3 <<'PY'
import base64
import os
import zlib

data = os.environ["HEADBRIDGE_SHARE_JSON"].encode("utf-8")
compressed = zlib.compress(data, 9)
raw_deflate = compressed[2:-4]
encoded = base64.urlsafe_b64encode(raw_deflate).decode("ascii").rstrip("=")
print(f"topflow://import?zip=deflate&data={encoded}")
PY
}

format_client_config_list() {
  endpoints="$1"
  relay="${2:-off}"
  vvip_enabled="false"
  [ -n "$relay" ] && [ "$relay" != "off" ] && vvip_enabled="true"
  count=$(printf '%s\n' "$endpoints" | sed '/^$/d' | wc -l | tr -d ' ')
  index=1
  printf '%s\n' "$endpoints" | while IFS= read -r endpoint; do
    endpoint=$(trim_value "$endpoint")
    [ -n "$endpoint" ] || continue
    parse_host_port "$endpoint" ""
    if [ "$count" -gt 1 ]; then
      label="node $index"
    else
      label="node"
    fi
    cat <<EOF
  ${label}:
    host        = $PARSED_HOST
    port        = $PARSED_PORT
    sni         = $HEADBRIDGE_SNI
    insecureTls = $HEADBRIDGE_SKIP_CERT_VERIFY
    vvipEnabled = $vvip_enabled
    vvipRelay   = $relay
    pskB64      = $HEADBRIDGE_PSK
    adminToken  = $HEADBRIDGE_ADMIN_TOKEN
    kernelType  = HeadBridge
EOF
    index=$((index + 1))
  done
}

write_env_file() {
  mkdir -p "$ETC_DIR"
  umask 027
  cat > "$ENV_FILE" <<EOF
HEADBRIDGE_LISTEN='$(escape_single_quotes "$HEADBRIDGE_LISTEN")'
HEADBRIDGE_PUBLIC_ENDPOINT='$(escape_single_quotes "$HEADBRIDGE_PUBLIC_ENDPOINT")'
HEADBRIDGE_NODE_NAME='$(escape_single_quotes "$HEADBRIDGE_NODE_NAME")'
HEADBRIDGE_GROUP_NAME='$(escape_single_quotes "$HEADBRIDGE_GROUP_NAME")'
HEADBRIDGE_SNI='$(escape_single_quotes "$HEADBRIDGE_SNI")'
HEADBRIDGE_PSK='$(escape_single_quotes "$HEADBRIDGE_PSK")'
HEADBRIDGE_MAX_CONNECTIONS='$(escape_single_quotes "$HEADBRIDGE_MAX_CONNECTIONS")'
HEADBRIDGE_MAX_CONNECTIONS_PER_IP='$(escape_single_quotes "$HEADBRIDGE_MAX_CONNECTIONS_PER_IP")'
HEADBRIDGE_VVIP_RELAY_LISTEN='$(escape_single_quotes "$HEADBRIDGE_VVIP_RELAY_LISTEN")'
HEADBRIDGE_SKIP_CERT_VERIFY='$(escape_single_quotes "$HEADBRIDGE_SKIP_CERT_VERIFY")'
HEADBRIDGE_DEBUG='$(escape_single_quotes "$HEADBRIDGE_DEBUG")'
HEADBRIDGE_CA_CERT='$(escape_single_quotes "$HEADBRIDGE_CA_CERT")'
HEADBRIDGE_CA_KEY='$(escape_single_quotes "$HEADBRIDGE_CA_KEY")'
HEADBRIDGE_GENERATE_CA='$(escape_single_quotes "$HEADBRIDGE_GENERATE_CA")'
HEADBRIDGE_EXTRA_ARGS='$(escape_single_quotes "$HEADBRIDGE_EXTRA_ARGS")'
HEADBRIDGE_ADMIN_TOKEN='$(escape_single_quotes "$HEADBRIDGE_ADMIN_TOKEN")'
HEADBRIDGE_FORWARDING_CONFIG='$(escape_single_quotes "$HEADBRIDGE_FORWARDING_CONFIG")'
HEADBRIDGE_VIDEO_HONEYPOT='$(escape_single_quotes "$HEADBRIDGE_VIDEO_HONEYPOT")'
EOF
  chmod 0640 "$ENV_FILE"
  chown root:"$HEADBRIDGE_GROUP" "$ENV_FILE"
}

write_runner_script() {
  cat > "$RUNNER_PATH" <<EOF
#!/bin/sh
set -eu

APP_DIR='${INSTALL_DIR}'
ENV_FILE='${ENV_FILE}'
BIN_PATH='${BIN_PATH}'

if [ -f "\$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "\$ENV_FILE"
fi

set -- \
  --listen "\${HEADBRIDGE_LISTEN:-${DEFAULT_LISTEN}}" \
  --max-connections "\${HEADBRIDGE_MAX_CONNECTIONS:-${DEFAULT_MAX_CONNECTIONS}}" \
  --max-connections-per-ip "\${HEADBRIDGE_MAX_CONNECTIONS_PER_IP:-${DEFAULT_MAX_CONNECTIONS_PER_IP}}" \
  --forwarding-config "\${HEADBRIDGE_FORWARDING_CONFIG:-${DEFAULT_FORWARDING_CONFIG}}"

VVIP_RELAY_LISTEN="\${HEADBRIDGE_VVIP_RELAY_LISTEN:-off}"
case "\$(printf '%s' "\$VVIP_RELAY_LISTEN" | tr '[:upper:]' '[:lower:]')" in
  0|false|no|off)
    ;;
  auto)
    LISTEN_VALUE="\${HEADBRIDGE_LISTEN:-${DEFAULT_LISTEN}}"
    case "\$LISTEN_VALUE" in
      \[*\]:*)
        LISTEN_HOST=\$(printf '%s' "\$LISTEN_VALUE" | sed -n 's/^\[\(.*\)\]:\([^:]*\)$/\1/p')
        LISTEN_PORT=\$(printf '%s' "\$LISTEN_VALUE" | sed -n 's/^\[\(.*\)\]:\([^:]*\)$/\2/p')
        ;;
      *:*)
        LISTEN_HOST=\${LISTEN_VALUE%:*}
        LISTEN_PORT=\${LISTEN_VALUE##*:}
        ;;
      *)
        LISTEN_HOST=\$LISTEN_VALUE
        LISTEN_PORT=""
        ;;
    esac
    if [ -n "\$LISTEN_PORT" ] && [ "\$LISTEN_PORT" -ge 1 ] 2>/dev/null && [ "\$LISTEN_PORT" -lt 65535 ] 2>/dev/null; then
      case "\$LISTEN_HOST" in
        *:*) VVIP_RELAY_LISTEN="[\$(printf '%s' "\$LISTEN_HOST" | sed 's/^\[//; s/\]$//')]:\$((LISTEN_PORT + 1))" ;;
        *) VVIP_RELAY_LISTEN="\${LISTEN_HOST}:\$((LISTEN_PORT + 1))" ;;
      esac
    else
      VVIP_RELAY_LISTEN=""
    fi
    ;;
esac

if [ -n "\$VVIP_RELAY_LISTEN" ]; then
  set -- "\$@" --vvip-relay-listen "\$VVIP_RELAY_LISTEN"
fi
if [ -n "\${HEADBRIDGE_PSK:-}" ]; then
  set -- "\$@" --psk "\$HEADBRIDGE_PSK"
fi
if [ -n "\${HEADBRIDGE_CA_CERT:-}" ]; then
  set -- "\$@" --ca-cert "\$HEADBRIDGE_CA_CERT"
fi
if [ -n "\${HEADBRIDGE_CA_KEY:-}" ]; then
  set -- "\$@" --ca-key "\$HEADBRIDGE_CA_KEY"
fi
if [ -n "\${HEADBRIDGE_ADMIN_TOKEN:-}" ]; then
  set -- "\$@" --admin-token "\$HEADBRIDGE_ADMIN_TOKEN"
fi
case "\$(printf '%s' "\${HEADBRIDGE_GENERATE_CA:-false}" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes|on) set -- "\$@" --generate-ca ;;
esac
case "\$(printf '%s' "\${HEADBRIDGE_SKIP_CERT_VERIFY:-true}" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes|on) set -- "\$@" --skip-cert-verify ;;
esac
case "\$(printf '%s' "\${HEADBRIDGE_DEBUG:-false}" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes|on) set -- "\$@" --debug ;;
esac
case "\$(printf '%s' "\${HEADBRIDGE_VIDEO_HONEYPOT:-true}" | tr '[:upper:]' '[:lower:]')" in
  0|false|no|off) set -- "\$@" --no-video-honeypot ;;
esac
if [ -n "\${HEADBRIDGE_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2086
  set -- "\$@" \$HEADBRIDGE_EXTRA_ARGS
fi

cd "\$APP_DIR"
exec "\$BIN_PATH" "\$@"
EOF
  chmod 0750 "$RUNNER_PATH"
  chown root:"$HEADBRIDGE_GROUP" "$RUNNER_PATH"
}

write_openrc_service() {
  cat > "$OPENRC_SERVICE" <<EOF
#!/sbin/openrc-run

name="${DISPLAY_NAME} Server"
description="HeadBridge server"
directory="${INSTALL_DIR}"
command="${RUNNER_PATH}"
command_user="${HEADBRIDGE_USER}:${HEADBRIDGE_GROUP}"
command_background="yes"
pidfile="${PID_FILE}"
retry="TERM/30/KILL/5"

depend() {
  need net
  use dns logger
}

start_pre() {
  checkpath --directory --mode 0755 --owner ${HEADBRIDGE_USER}:${HEADBRIDGE_GROUP} ${PID_DIR}
}
EOF
  chmod 0755 "$OPENRC_SERVICE"
}

enable_and_start_service() {
  log "enabling OpenRC service ${SERVICE_NAME}"
  rc-update add "$SERVICE_NAME" default >/dev/null 2>&1 || true
  rc-service "$SERVICE_NAME" start
  sleep 1
  rc-service "$SERVICE_NAME" status || die "service failed to start"
}

check_current_install() {
  [ -f "$BIN_PATH" ] || die "installed binary not found at $BIN_PATH"
  [ -f "$OPENRC_SERVICE" ] || die "OpenRC service not found at $OPENRC_SERVICE"
}

update_service() {
  log "replacing installed binary"
  install_binary
  configure_bind_capability
  rc-service "$SERVICE_NAME" restart
  sleep 1
  rc-service "$SERVICE_NAME" status || die "service failed after update"
}

confirm_uninstall() {
  is_true "$ASSUME_YES" && return 0
  printf 'Remove %s from this Alpine host? [y/N] ' "$DISPLAY_NAME"
  read answer || true
  case "$(lower "${answer:-n}")" in
    y|yes) ;;
    *) die "uninstall cancelled" ;;
  esac
}

disable_and_stop_service() {
  if [ -f "$OPENRC_SERVICE" ]; then
    rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
    rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
    rm -f "$OPENRC_SERVICE"
  fi
}

remove_runtime_user() {
  if is_true "$REMOVE_USER"; then
    if id "$HEADBRIDGE_USER" >/dev/null 2>&1; then
      deluser "$HEADBRIDGE_USER" >/dev/null 2>&1 || true
    fi
    if grep -q "^${HEADBRIDGE_GROUP}:" /etc/group 2>/dev/null; then
      delgroup "$HEADBRIDGE_GROUP" >/dev/null 2>&1 || true
    fi
  fi
}

print_connection_summary() {
  endpoints=$(detect_public_endpoints)
  endpoint_lines=$(printf '%s\n' "$endpoints" | sed '/^$/d; s/^/  /')
  relay_display=$(resolve_vvip_relay_listen "$HEADBRIDGE_LISTEN" "$HEADBRIDGE_VVIP_RELAY_LISTEN" || true)
  [ -n "$relay_display" ] || relay_display="off"
  config_lines=$(format_client_config_list "$endpoints" "$relay_display")
  link=$(build_topflow_link "$endpoints")

  cat <<EOF

HeadBridge Alpine deployment completed.

service name:    $SERVICE_NAME
listen:          $HEADBRIDGE_LISTEN
client address:
$endpoint_lines
node name:       $HEADBRIDGE_NODE_NAME
group name:      $HEADBRIDGE_GROUP_NAME
sni:             $HEADBRIDGE_SNI
psk:             $HEADBRIDGE_PSK
admin token:     $HEADBRIDGE_ADMIN_TOKEN
binary path:     $BIN_PATH
env file:        $ENV_FILE

client config:
$config_lines

share link:
$link

common commands:
  rc-service $SERVICE_NAME status
  rc-service $SERVICE_NAME restart
  cat $ENV_FILE
EOF

  if printf '%s\n' "$endpoints" | grep -q 'REPLACE_WITH_PUBLIC_HOST'; then
    warn "public endpoint detection failed; reinstall with --public-endpoint your.domain.com:6379 or manually replace the host in the share link"
  fi
}

main_install() {
  require_root
  install_dependencies
  ensure_openrc
  ensure_runtime_user
  generate_or_validate_psk
  generate_or_validate_admin_token
  install_binary
  configure_bind_capability
  write_env_file
  write_runner_script
  write_openrc_service
  enable_and_start_service
  print_connection_summary
}

main_update() {
  require_root
  ensure_openrc
  check_current_install
  load_env_if_exists
  generate_or_validate_psk
  generate_or_validate_admin_token
  write_env_file
  write_runner_script
  update_service
  print_connection_summary
}

main_uninstall() {
  require_root
  ensure_openrc
  confirm_uninstall
  disable_and_stop_service
  rm -rf "$INSTALL_DIR"
  if ! is_true "$KEEP_CONFIG"; then
    rm -rf "$ETC_DIR"
  fi
  rm -rf "$PID_DIR"
  remove_runtime_user
  log "uninstall completed"
}

COMMAND="${1:-}"
case "$COMMAND" in
  install)
    shift
    parse_install_args "$@"
    main_install
    ;;
  update)
    shift
    parse_update_args "$@"
    main_update
    ;;
  uninstall)
    shift
    parse_uninstall_args "$@"
    main_uninstall
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    die "unknown command: $COMMAND"
    ;;
esac
