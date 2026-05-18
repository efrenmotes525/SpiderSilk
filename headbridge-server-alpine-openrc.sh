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
ALPINE_DEPENDENCIES="ca-certificates curl openssl openrc libcap"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

SERVICE_NAME="${HEADBRIDGE_SERVICE_NAME:-$DEFAULT_SERVICE_NAME}"
INSTALL_DIR="${HEADBRIDGE_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
ETC_DIR="${HEADBRIDGE_ETC_DIR:-$DEFAULT_ETC_DIR}"
HEADBRIDGE_USER="${HEADBRIDGE_USER:-headbridge}"
HEADBRIDGE_GROUP="${HEADBRIDGE_GROUP:-headbridge}"

HEADBRIDGE_LISTEN="${HEADBRIDGE_LISTEN:-$DEFAULT_LISTEN}"
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
EOF
}

parse_install_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --psk) HEADBRIDGE_PSK="$2"; shift 2 ;;
      --listen) HEADBRIDGE_LISTEN="$2"; shift 2 ;;
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

write_env_file() {
  mkdir -p "$ETC_DIR"
  umask 027
  cat > "$ENV_FILE" <<EOF
HEADBRIDGE_LISTEN='$(escape_single_quotes "$HEADBRIDGE_LISTEN")'
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

print_install_summary() {
  relay_value=$(resolve_vvip_relay_listen "$HEADBRIDGE_LISTEN" "$HEADBRIDGE_VVIP_RELAY_LISTEN" || true)
  log "service name: $SERVICE_NAME"
  log "binary path: $BIN_PATH"
  log "env file: $ENV_FILE"
  log "listen: $HEADBRIDGE_LISTEN"
  if [ -n "$relay_value" ]; then
    log "vvip relay listen: $relay_value"
  fi
  log "psk: $HEADBRIDGE_PSK"
  log "admin token: $HEADBRIDGE_ADMIN_TOKEN"
  log "client host port: 6379 by default; fill this admin token in TopFlow if adding the node manually"
  log "config file keeps secrets at: $ENV_FILE"
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
  print_install_summary
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
