#!/usr/bin/env bash
set -euo pipefail

APP_NAME="headbridge-server"
DISPLAY_NAME="HeadBridge"
DEFAULT_SERVICE_NAME="headbridge-server"
DEFAULT_INSTALL_DIR="/opt/headbridge-server"
DEFAULT_ETC_DIR="/etc/headbridge-server"
DEFAULT_DOWNLOAD_URL="https://github.com/efrenmotes525/SpiderSilk/raw/refs/heads/main/headbridge-server"
DEFAULT_USER="headbridge"
DEFAULT_GROUP="headbridge"
DEFAULT_LISTEN="0.0.0.0:8888"
DEFAULT_MAX_CONNECTIONS="10000"

first_non_empty() {
  local name value
  for name in "$@"; do
    value="${!name:-}"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
  return 1
}

env_or_default() {
  local default="$1"
  shift
  local value
  if value="$(first_non_empty "$@")"; then
    printf '%s' "$value"
  else
    printf '%s' "$default"
  fi
}

SERVICE_NAME="$(env_or_default "$DEFAULT_SERVICE_NAME" HEADBRIDGE_SERVICE_NAME TOPFLOW_SERVICE_NAME)"
INSTALL_DIR="$(env_or_default "$DEFAULT_INSTALL_DIR" HEADBRIDGE_INSTALL_DIR TOPFLOW_INSTALL_DIR)"
ETC_DIR="$(env_or_default "$DEFAULT_ETC_DIR" HEADBRIDGE_ETC_DIR TOPFLOW_ETC_DIR)"
HEADBRIDGE_USER="$(env_or_default "$DEFAULT_USER" HEADBRIDGE_USER TOPFLOW_USER)"
HEADBRIDGE_GROUP="$(env_or_default "$DEFAULT_GROUP" HEADBRIDGE_GROUP TOPFLOW_GROUP)"

HEADBRIDGE_LISTEN="$(env_or_default "$DEFAULT_LISTEN" HEADBRIDGE_LISTEN TOPFLOW_LISTEN)"
HEADBRIDGE_PSK="$(env_or_default "" HEADBRIDGE_PSK TOPFLOW_PSK)"
HEADBRIDGE_MAX_CONNECTIONS="$(env_or_default "$DEFAULT_MAX_CONNECTIONS" HEADBRIDGE_MAX_CONNECTIONS TOPFLOW_MAX_CONNECTIONS)"
HEADBRIDGE_SKIP_CERT_VERIFY="$(env_or_default "true" HEADBRIDGE_SKIP_CERT_VERIFY TOPFLOW_SKIP_CERT_VERIFY)"
HEADBRIDGE_DEBUG="$(env_or_default "false" HEADBRIDGE_DEBUG TOPFLOW_DEBUG)"
HEADBRIDGE_CA_CERT="$(env_or_default "" HEADBRIDGE_CA_CERT TOPFLOW_CA_CERT)"
HEADBRIDGE_CA_KEY="$(env_or_default "" HEADBRIDGE_CA_KEY TOPFLOW_CA_KEY)"
HEADBRIDGE_GENERATE_CA="$(env_or_default "false" HEADBRIDGE_GENERATE_CA TOPFLOW_GENERATE_CA)"
HEADBRIDGE_EXTRA_ARGS="$(env_or_default "" HEADBRIDGE_EXTRA_ARGS TOPFLOW_EXTRA_ARGS)"
HEADBRIDGE_OPEN_FIREWALL="$(env_or_default "true" HEADBRIDGE_OPEN_FIREWALL TOPFLOW_OPEN_FIREWALL)"
HEADBRIDGE_DOWNLOAD_URL="$(env_or_default "$DEFAULT_DOWNLOAD_URL" HEADBRIDGE_DOWNLOAD_URL TOPFLOW_DOWNLOAD_URL)"

KEEP_CONFIG="${KEEP_CONFIG:-false}"
REMOVE_USER="${REMOVE_USER:-true}"
ASSUME_YES="${ASSUME_YES:-false}"

refresh_paths() {
  BIN_PATH="${INSTALL_DIR}/${APP_NAME}"
  RUNNER_PATH="${INSTALL_DIR}/run-headbridge-server.sh"
  ENV_FILE="${ETC_DIR}/headbridge-server.env"
  SYSTEMD_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
}

refresh_paths

log() {
  printf '\033[1;36m[%s]\033[0m %s\n' "$DISPLAY_NAME" "$*"
}

warn() {
  printf '\033[1;33m[%s]\033[0m %s\n' "$DISPLAY_NAME" "$*" >&2
}

die() {
  printf '\033[1;31m[%s]\033[0m %s\n' "$DISPLAY_NAME" "$*" >&2
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

resolve_path() {
  local target="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$target"
    return 0
  fi
  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$target" 2>/dev/null && return 0
  fi
  printf '%s' "$target"
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "??? root ? sudo ??????"
}

ensure_systemd() {
  command -v systemctl >/dev/null 2>&1 || die "???????? systemctl?"
  [[ -d /run/systemd/system ]] || die "?????? systemd ??????????????"
}

usage() {
  cat <<'EOF'
HeadBridge ?????????

???
  sudo bash headbridge-server.sh install   [????...]
  sudo bash headbridge-server.sh update    [????...]
  sudo bash headbridge-server.sh uninstall [????...]

????
  install     ????? systemd ??
  update      ??????????????????
  uninstall   ??????????????

?????
  --psk <Base64>            ?? 32 ?? PSK ? Base64 ???????????
  --listen <host:port>      ??????? 0.0.0.0:8888
  --max-connections <num>   ???????? 10000
  --download-url <url>      ??????????
  --ca-cert <path>          ????? CA ????
  --ca-key <path>           ????? CA ????
  --generate-ca             ????? CA
  --debug / -d              ??????
  --skip-cert-verify        ??????
  --no-firewall             ????????
  --user <name>             ????????? headbridge
  --group <name>            ???????? headbridge
  --service-name <name>     systemd ?????? headbridge-server
  --install-dir <dir>       ??????? /opt/headbridge-server
  --etc-dir <dir>           ??????? /etc/headbridge-server

?????
  --download-url <url>      ??????????
  --service-name <name>     systemd ???
  --install-dir <dir>       ????
  --etc-dir <dir>           ????

?????
  --yes                     ??????
  --keep-config             ??????
  --keep-user               ??????????
  --service-name <name>     systemd ???
  --install-dir <dir>       ????
  --etc-dir <dir>           ????

?????????
  HEADBRIDGE_PSK / HEADBRIDGE_LISTEN / HEADBRIDGE_DOWNLOAD_URL / HEADBRIDGE_DEBUG ?

???????
  TOPFLOW_PSK / TOPFLOW_LISTEN / TOPFLOW_DOWNLOAD_URL / TOPFLOW_DEBUG ?
EOF
}

parse_install_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --psk) HEADBRIDGE_PSK="$2"; shift 2 ;;
      --listen) HEADBRIDGE_LISTEN="$2"; shift 2 ;;
      --max-connections) HEADBRIDGE_MAX_CONNECTIONS="$2"; shift 2 ;;
      --download-url) HEADBRIDGE_DOWNLOAD_URL="$2"; shift 2 ;;
      --ca-cert) HEADBRIDGE_CA_CERT="$2"; shift 2 ;;
      --ca-key) HEADBRIDGE_CA_KEY="$2"; shift 2 ;;
      --generate-ca) HEADBRIDGE_GENERATE_CA="true"; shift ;;
      --debug|-d) HEADBRIDGE_DEBUG="true"; shift ;;
      --skip-cert-verify) HEADBRIDGE_SKIP_CERT_VERIFY="true"; shift ;;
      --no-firewall) HEADBRIDGE_OPEN_FIREWALL="false"; shift ;;
      --user) HEADBRIDGE_USER="$2"; shift 2 ;;
      --group) HEADBRIDGE_GROUP="$2"; shift 2 ;;
      --service-name) SERVICE_NAME="$2"; shift 2 ;;
      --install-dir) INSTALL_DIR="$2"; shift 2 ;;
      --etc-dir) ETC_DIR="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "install ?????$1" ;;
    esac
  done
  refresh_paths
}

parse_update_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --download-url) HEADBRIDGE_DOWNLOAD_URL="$2"; shift 2 ;;
      --service-name) SERVICE_NAME="$2"; shift 2 ;;
      --install-dir) INSTALL_DIR="$2"; shift 2 ;;
      --etc-dir) ETC_DIR="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "update ?????$1" ;;
    esac
  done
  refresh_paths
}

parse_uninstall_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) ASSUME_YES="true"; shift ;;
      --keep-config) KEEP_CONFIG="true"; shift ;;
      --keep-user) REMOVE_USER="false"; shift ;;
      --service-name) SERVICE_NAME="$2"; shift 2 ;;
      --install-dir) INSTALL_DIR="$2"; shift 2 ;;
      --etc-dir) ETC_DIR="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "uninstall ?????$1" ;;
    esac
  done
  refresh_paths
}

install_dependencies() {
  log "??????..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl tar gzip openssl >/dev/null
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ca-certificates curl tar gzip openssl shadow-utils >/dev/null
  elif command -v yum >/dev/null 2>&1; then
    yum install -y ca-certificates curl tar gzip openssl shadow-utils >/dev/null
  else
    die "?????????????????????? curl / openssl / systemd?"
  fi
}

ensure_runtime_user() {
  if ! getent group "$HEADBRIDGE_GROUP" >/dev/null 2>&1; then
    groupadd --system "$HEADBRIDGE_GROUP"
  fi

  if ! id "$HEADBRIDGE_USER" >/dev/null 2>&1; then
    local no_login_shell="/usr/sbin/nologin"
    [[ -x "$no_login_shell" ]] || no_login_shell="/sbin/nologin"
    [[ -x "$no_login_shell" ]] || no_login_shell="/bin/false"
    useradd --system --gid "$HEADBRIDGE_GROUP" --home-dir "$INSTALL_DIR" --create-home --shell "$no_login_shell" "$HEADBRIDGE_USER"
  fi
}

ensure_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)
      ;;
    aarch64|arm64)
      if [[ "$HEADBRIDGE_DOWNLOAD_URL" == "$DEFAULT_DOWNLOAD_URL" ]]; then
        die "??????????? x86_64?ARM ?????? --download-url ?? ARM ??????"
      fi
      ;;
    *)
      if [[ "$HEADBRIDGE_DOWNLOAD_URL" == "$DEFAULT_DOWNLOAD_URL" ]]; then
        die "???? ${arch} ???????????? --download-url ?????????"
      fi
      ;;
  esac
}

generate_or_validate_psk() {
  if [[ -z "$HEADBRIDGE_PSK" ]]; then
    HEADBRIDGE_PSK="$(openssl rand -base64 32 | tr -d '\r\n')"
    log "??? PSK???????"
  fi

  local decoded_len
  decoded_len="$(printf '%s' "$HEADBRIDGE_PSK" | base64 -d 2>/dev/null | wc -c | tr -d ' ')"
  [[ "$decoded_len" == "32" ]] || die "PSK ??? Base64 ?????????? 32 ???"
}

load_env_if_exists() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    HEADBRIDGE_LISTEN="${HEADBRIDGE_LISTEN:-${TOPFLOW_LISTEN:-$HEADBRIDGE_LISTEN}}"
    HEADBRIDGE_PSK="${HEADBRIDGE_PSK:-${TOPFLOW_PSK:-$HEADBRIDGE_PSK}}"
    HEADBRIDGE_MAX_CONNECTIONS="${HEADBRIDGE_MAX_CONNECTIONS:-${TOPFLOW_MAX_CONNECTIONS:-$HEADBRIDGE_MAX_CONNECTIONS}}"
    HEADBRIDGE_SKIP_CERT_VERIFY="${HEADBRIDGE_SKIP_CERT_VERIFY:-${TOPFLOW_SKIP_CERT_VERIFY:-$HEADBRIDGE_SKIP_CERT_VERIFY}}"
    HEADBRIDGE_DEBUG="${HEADBRIDGE_DEBUG:-${TOPFLOW_DEBUG:-$HEADBRIDGE_DEBUG}}"
    HEADBRIDGE_CA_CERT="${HEADBRIDGE_CA_CERT:-${TOPFLOW_CA_CERT:-$HEADBRIDGE_CA_CERT}}"
    HEADBRIDGE_CA_KEY="${HEADBRIDGE_CA_KEY:-${TOPFLOW_CA_KEY:-$HEADBRIDGE_CA_KEY}}"
    HEADBRIDGE_GENERATE_CA="${HEADBRIDGE_GENERATE_CA:-${TOPFLOW_GENERATE_CA:-$HEADBRIDGE_GENERATE_CA}}"
    HEADBRIDGE_EXTRA_ARGS="${HEADBRIDGE_EXTRA_ARGS:-${TOPFLOW_EXTRA_ARGS:-$HEADBRIDGE_EXTRA_ARGS}}"
    HEADBRIDGE_DOWNLOAD_URL="${HEADBRIDGE_DOWNLOAD_URL:-${TOPFLOW_DOWNLOAD_URL:-$HEADBRIDGE_DOWNLOAD_URL}}"
  fi
}

download_binary_to_temp() {
  local tmp_file
  tmp_file="$(mktemp)"
  curl -fsSL "$HEADBRIDGE_DOWNLOAD_URL" -o "$tmp_file"
  if head -n 5 "$tmp_file" | grep -q 'git-lfs.github.com/spec'; then
    rm -f "$tmp_file"
    die "????? Git LFS ?????????????"
  fi
  chmod 0755 "$tmp_file"
  echo "$tmp_file"
}

install_binary() {
  log "?????????$HEADBRIDGE_DOWNLOAD_URL"
  mkdir -p "$INSTALL_DIR" "$ETC_DIR"
  local tmp_file
  tmp_file="$(download_binary_to_temp)"
  trap 'rm -f "${tmp_file:-}"' RETURN
  install -m 0755 "$tmp_file" "$BIN_PATH"
  chown root:"$HEADBRIDGE_GROUP" "$BIN_PATH"
  if ! "$BIN_PATH" --help >/dev/null 2>&1; then
    warn "???????????????????????????????"
  fi
}

write_env_file() {
  log "???????$ENV_FILE"
  cat > "$ENV_FILE" <<EOF
HEADBRIDGE_LISTEN='$(escape_single_quotes "$HEADBRIDGE_LISTEN")'
HEADBRIDGE_PSK='$(escape_single_quotes "$HEADBRIDGE_PSK")'
HEADBRIDGE_MAX_CONNECTIONS='$(escape_single_quotes "$HEADBRIDGE_MAX_CONNECTIONS")'
HEADBRIDGE_SKIP_CERT_VERIFY='$(escape_single_quotes "$HEADBRIDGE_SKIP_CERT_VERIFY")'
HEADBRIDGE_DEBUG='$(escape_single_quotes "$HEADBRIDGE_DEBUG")'
HEADBRIDGE_CA_CERT='$(escape_single_quotes "$HEADBRIDGE_CA_CERT")'
HEADBRIDGE_CA_KEY='$(escape_single_quotes "$HEADBRIDGE_CA_KEY")'
HEADBRIDGE_GENERATE_CA='$(escape_single_quotes "$HEADBRIDGE_GENERATE_CA")'
HEADBRIDGE_EXTRA_ARGS='$(escape_single_quotes "$HEADBRIDGE_EXTRA_ARGS")'
HEADBRIDGE_DOWNLOAD_URL='$(escape_single_quotes "$HEADBRIDGE_DOWNLOAD_URL")'
EOF
  chown root:"$HEADBRIDGE_GROUP" "$ENV_FILE"
  chmod 0640 "$ENV_FILE"
}

write_runner() {
  log "?????????$RUNNER_PATH"
  cat > "$RUNNER_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$ENV_FILE"
BIN_PATH="$BIN_PATH"

if [[ ! -f "\$ENV_FILE" ]]; then
  echo "HeadBridge env file not found: \$ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "\$ENV_FILE"

LISTEN="\${HEADBRIDGE_LISTEN:-\${TOPFLOW_LISTEN:-0.0.0.0:8888}}"
PSK="\${HEADBRIDGE_PSK:-\${TOPFLOW_PSK:-}}"
MAX_CONNECTIONS="\${HEADBRIDGE_MAX_CONNECTIONS:-\${TOPFLOW_MAX_CONNECTIONS:-10000}}"
SKIP_CERT_VERIFY="\${HEADBRIDGE_SKIP_CERT_VERIFY:-\${TOPFLOW_SKIP_CERT_VERIFY:-true}}"
DEBUG_FLAG="\${HEADBRIDGE_DEBUG:-\${TOPFLOW_DEBUG:-false}}"
CA_CERT="\${HEADBRIDGE_CA_CERT:-\${TOPFLOW_CA_CERT:-}}"
CA_KEY="\${HEADBRIDGE_CA_KEY:-\${TOPFLOW_CA_KEY:-}}"
GENERATE_CA="\${HEADBRIDGE_GENERATE_CA:-\${TOPFLOW_GENERATE_CA:-false}}"
EXTRA_ARGS="\${HEADBRIDGE_EXTRA_ARGS:-\${TOPFLOW_EXTRA_ARGS:-}}"

args=(--listen "\$LISTEN" --max-connections "\$MAX_CONNECTIONS")

if [[ -n "\$PSK" ]]; then
  args+=(--psk "\$PSK")
fi
if [[ -n "\$CA_CERT" ]]; then
  args+=(--ca-cert "\$CA_CERT")
fi
if [[ -n "\$CA_KEY" ]]; then
  args+=(--ca-key "\$CA_KEY")
fi
if [[ "\$GENERATE_CA" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  args+=(--generate-ca)
fi
if [[ "\$SKIP_CERT_VERIFY" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  args+=(--skip-cert-verify)
fi
if [[ "\$DEBUG_FLAG" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  args+=(--debug)
fi
if [[ -n "\$EXTRA_ARGS" ]]; then
  # shellcheck disable=SC2206
  extra_args=(\$EXTRA_ARGS)
  args+=("\${extra_args[@]}")
fi

exec "\$BIN_PATH" "\${args[@]}"
EOF
  chmod 0750 "$RUNNER_PATH"
  chown root:"$HEADBRIDGE_GROUP" "$RUNNER_PATH"
}

write_systemd_unit() {
  log "?? systemd ???$SERVICE_NAME"
  cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=HeadBridge Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$HEADBRIDGE_USER
Group=$HEADBRIDGE_GROUP
WorkingDirectory=$INSTALL_DIR
ExecStart=$RUNNER_PATH
Restart=always
RestartSec=2
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
}

configure_firewall_add() {
  is_true "$HEADBRIDGE_OPEN_FIREWALL" || return 0
  local port="${HEADBRIDGE_LISTEN##*:}"
  [[ "$port" =~ ^[0-9]+$ ]] || {
    warn "??? listen ??????????$HEADBRIDGE_LISTEN??????????"
    return 0
  }

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi 'Status: active'; then
    log "??? UFW????? ${port}/tcp"
    ufw allow "${port}/tcp" >/dev/null || warn "UFW ???????????ufw allow ${port}/tcp"
    return 0
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    log "??? firewalld????? ${port}/tcp"
    firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null || warn "firewalld ???????????firewall-cmd --permanent --add-port=${port}/tcp"
    firewall-cmd --reload >/dev/null || true
    return 0
  fi
  warn "??????? UFW / firewalld??????????"
}

configure_firewall_remove() {
  local listen_value="${HEADBRIDGE_LISTEN:-${TOPFLOW_LISTEN:-}}"
  [[ -n "$listen_value" ]] || return 0
  local port="${listen_value##*:}"
  [[ "$port" =~ ^[0-9]+$ ]] || return 0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi 'Status: active'; then
    ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --remove-port="${port}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
}

enable_and_start_service() {
  log "?????????..."
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null
  systemctl restart "$SERVICE_NAME"
  sleep 1
  systemctl --no-pager --full status "$SERVICE_NAME" || {
    journalctl -u "$SERVICE_NAME" -n 80 --no-pager || true
    die "????????????????"
  }
}

check_current_install() {
  [[ -f "$BIN_PATH" ]] || die "??????????$BIN_PATH"
  systemctl cat "$SERVICE_NAME" >/dev/null 2>&1 || die "??? systemd ???$SERVICE_NAME"
}

update_server() {
  require_root
  ensure_systemd
  local args=("$@")
  parse_update_args "${args[@]}"
  load_env_if_exists
  parse_update_args "${args[@]}"
  ensure_arch
  check_current_install

  log "?????$HEADBRIDGE_DOWNLOAD_URL"
  local new_bin
  new_bin="$(download_binary_to_temp)"
  trap 'rm -f "${new_bin:-}"' EXIT

  "$new_bin" --help >/dev/null 2>&1 || die "???????????? --help??????"

  local backup_path="${BIN_PATH}.bak.$(date +%Y%m%d-%H%M%S)"
  cp -f "$BIN_PATH" "$backup_path"
  install -m 0755 "$new_bin" "$BIN_PATH"
  write_env_file

  if systemctl restart "$SERVICE_NAME"; then
    systemctl --no-pager --full status "$SERVICE_NAME" || true
    log "??????????$backup_path"
    return 0
  fi

  log "???????????????..."
  install -m 0755 "$backup_path" "$BIN_PATH"
  systemctl restart "$SERVICE_NAME" || true
  journalctl -u "$SERVICE_NAME" -n 80 --no-pager || true
  die "???????????????"
}

confirm_uninstall() {
  if is_true "$ASSUME_YES"; then
    return 0
  fi
  printf "???? ${DISPLAY_NAME} ??????????? systemd ???????%s [y/N]: " "$(is_true "$KEEP_CONFIG" && printf '???????' || printf '?????')"
  read -r answer
  case "$(lower "$answer")" in
    y|yes) ;;
    *) die "??????" ;;
  esac
}

uninstall_server() {
  require_root
  local args=("$@")
  parse_uninstall_args "${args[@]}"
  load_env_if_exists
  parse_uninstall_args "${args[@]}"
  confirm_uninstall

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
  fi

  configure_firewall_remove
  rm -f "$SYSTEMD_UNIT"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed >/dev/null 2>&1 || true
  fi

  rm -rf "$INSTALL_DIR"
  if ! is_true "$KEEP_CONFIG"; then
    rm -rf "$ETC_DIR"
  fi

  if is_true "$REMOVE_USER"; then
    if id "$HEADBRIDGE_USER" >/dev/null 2>&1; then
      userdel "$HEADBRIDGE_USER" >/dev/null 2>&1 || warn "???? $HEADBRIDGE_USER ?????????"
    fi
    if getent group "$HEADBRIDGE_GROUP" >/dev/null 2>&1; then
      groupdel "$HEADBRIDGE_GROUP" >/dev/null 2>&1 || warn "????? $HEADBRIDGE_GROUP ?????????"
    fi
  fi

  log "${DISPLAY_NAME} ?????????"
}

install_server() {
  require_root
  ensure_systemd
  parse_install_args "$@"
  install_dependencies
  ensure_arch
  generate_or_validate_psk
  ensure_runtime_user
  install_binary
  write_env_file
  write_runner
  write_systemd_unit
  configure_firewall_add
  enable_and_start_service

  local script_path
  script_path="$(resolve_path "$0")"

  cat <<EOF

${DISPLAY_NAME} ????????

????:  $SERVICE_NAME
????:  $HEADBRIDGE_LISTEN
PSK:       $HEADBRIDGE_PSK
???:    $BIN_PATH
????:  $ENV_FILE
????:  $script_path

????:
  systemctl status $SERVICE_NAME --no-pager
  systemctl restart $SERVICE_NAME
  journalctl -u $SERVICE_NAME -f
  sudo bash $script_path update
  sudo bash $script_path uninstall --yes
EOF
}

main() {
  local command="${1:-}"
  [[ -n "$command" ]] || { usage; exit 1; }
  shift || true

  case "$command" in
    install) install_server "$@" ;;
    update) update_server "$@" ;;
    uninstall) uninstall_server "$@" ;;
    -h|--help|help) usage ;;
    *) die "??????$command" ;;
  esac
}

main "$@"
