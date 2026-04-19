#!/usr/bin/env bash
set -euo pipefail

APP_NAME="headbridge-server"
DISPLAY_NAME="TopFlow"
DEFAULT_SERVICE_NAME="topflow-server"
DEFAULT_INSTALL_DIR="/opt/topflow-server"
DEFAULT_ETC_DIR="/etc/topflow-server"
DEFAULT_DOWNLOAD_URL="https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/headbridge-server"

SERVICE_NAME="${TOPFLOW_SERVICE_NAME:-topflow-server}"
INSTALL_DIR="${TOPFLOW_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
ETC_DIR="${TOPFLOW_ETC_DIR:-$DEFAULT_ETC_DIR}"
TOPFLOW_USER="${TOPFLOW_USER:-topflow}"
TOPFLOW_GROUP="${TOPFLOW_GROUP:-topflow}"

TOPFLOW_LISTEN="${TOPFLOW_LISTEN:-0.0.0.0:8888}"
TOPFLOW_PUBLIC_ENDPOINT="${TOPFLOW_PUBLIC_ENDPOINT:-}"
TOPFLOW_NODE_NAME="${TOPFLOW_NODE_NAME:-TopFlow}"
TOPFLOW_GROUP_NAME="${TOPFLOW_GROUP_NAME:-AutoDeploy}"
TOPFLOW_SNI="${TOPFLOW_SNI:-www.cloudflare.com}"
TOPFLOW_PSK="${TOPFLOW_PSK:-}"
TOPFLOW_MAX_CONNECTIONS="${TOPFLOW_MAX_CONNECTIONS:-10000}"
TOPFLOW_SKIP_CERT_VERIFY="${TOPFLOW_SKIP_CERT_VERIFY:-true}"
TOPFLOW_DEBUG="${TOPFLOW_DEBUG:-false}"
TOPFLOW_CA_CERT="${TOPFLOW_CA_CERT:-}"
TOPFLOW_CA_KEY="${TOPFLOW_CA_KEY:-}"
TOPFLOW_GENERATE_CA="${TOPFLOW_GENERATE_CA:-false}"
TOPFLOW_EXTRA_ARGS="${TOPFLOW_EXTRA_ARGS:-}"
TOPFLOW_OPEN_FIREWALL="${TOPFLOW_OPEN_FIREWALL:-true}"
TOPFLOW_DOWNLOAD_URL="${TOPFLOW_DOWNLOAD_URL:-$DEFAULT_DOWNLOAD_URL}"

KEEP_CONFIG="${KEEP_CONFIG:-false}"
REMOVE_USER="${REMOVE_USER:-true}"
ASSUME_YES="${ASSUME_YES:-false}"

refresh_paths() {
  BIN_PATH="${INSTALL_DIR}/${APP_NAME}"
  RUNNER_PATH="${INSTALL_DIR}/run-topflow-server.sh"
  ENV_FILE="${ETC_DIR}/topflow-server.env"
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

normalize_host() {
  local host="${1:-}"
  host="${host#[}"
  host="${host%]}"
  printf '%s' "$host"
}

parse_host_port() {
  local value="${1:-}"
  local default_port="${2:-}"
  local host port

  if [[ "$value" =~ ^\[([^][]+)\]:(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    port="${BASH_REMATCH[2]}"
  elif [[ "$value" == *:* ]]; then
    host="${value%:*}"
    port="${value##*:}"
  else
    host="$value"
    port="$default_port"
  fi

  PARSED_HOST="$(normalize_host "$host")"
  PARSED_PORT="$port"
}

format_endpoint() {
  local host
  host="$(normalize_host "$1")"
  local port="$2"

  if [[ "$host" == *:* ]]; then
    printf '[%s]:%s' "$host" "$port"
  else
    printf '%s:%s' "$host" "$port"
  fi
}

is_wildcard_host() {
  local host
  host="$(normalize_host "$1")"
  [[ "$host" == "0.0.0.0" || "$host" == "::" ]]
}

listen_port_requires_privileged_bind() {
  local port
  parse_host_port "$TOPFLOW_LISTEN"
  port="$PARSED_PORT"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port < 1024 ))
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
  [[ "$(id -u)" -eq 0 ]] || die "请使用 root 或 sudo 执行此脚本。"
}

ensure_systemd() {
  command -v systemctl >/dev/null 2>&1 || die "当前系统未检测到 systemctl。"
  [[ -d /run/systemd/system ]] || die "当前环境不是 systemd 主机环境，无法自动托管服务。"
}

usage() {
  cat <<'EOF'
TopFlow 服务端统一管理脚本

用法：
  sudo bash topflow-server.sh install   [安装参数...]
  sudo bash topflow-server.sh update    [更新参数...]
  sudo bash topflow-server.sh uninstall [卸载参数...]

子命令：
  install     安装并注册 systemd 服务
  update      下载新二进制并滚动更新，失败自动回滚
  uninstall   卸载服务、文件、可选保留配置

安装参数：
  --psk <Base64>              指定 32 字节 PSK 的 Base64 字符串；不传则自动生成
  --listen <host:port>        监听地址，默认 0.0.0.0:8888；IPv6 建议写成 [::]:8888
  --public-endpoint <h:p>     给客户端展示的公网地址，例如 1.2.3.4:8443 / [2001:db8::1]:8443
  --node-name <name>          客户端节点名称，默认 TopFlow
  --group-name <name>         客户端分组名称，默认 AutoDeploy
  --sni <host>                客户端配置中的 SNI，默认 www.cloudflare.com
  --max-connections <num>     最大连接数，默认 10000
  --download-url <url>        服务端二进制下载地址
  --ca-cert <path>            可选，指定 CA 证书路径
  --ca-key <path>             可选，指定 CA 私钥路径
  --generate-ca               启动时生成 CA
  --debug / -d                打开调试日志
  --skip-cert-verify          透传给服务端，同时导出 insecureTls=true
  --no-firewall               不自动放行防火墙
  --user <name>               服务运行用户，默认 topflow
  --group <name>              服务运行组，默认 topflow
  --service-name <name>       systemd 服务名，默认 topflow-server
  --install-dir <dir>         安装目录，默认 /opt/topflow-server
  --etc-dir <dir>             配置目录，默认 /etc/topflow-server

更新参数：
  --download-url <url>        新的服务端二进制地址
  --service-name <name>       systemd 服务名
  --install-dir <dir>         安装目录
  --etc-dir <dir>             配置目录

卸载参数：
  --yes                       不再二次确认
  --keep-config               保留配置目录
  --keep-user                 保留运行用户和用户组
  --service-name <name>       systemd 服务名
  --install-dir <dir>         安装目录
  --etc-dir <dir>             配置目录
EOF
}

parse_install_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --psk) TOPFLOW_PSK="$2"; shift 2 ;;
      --listen) TOPFLOW_LISTEN="$2"; shift 2 ;;
      --public-endpoint) TOPFLOW_PUBLIC_ENDPOINT="$2"; shift 2 ;;
      --node-name) TOPFLOW_NODE_NAME="$2"; shift 2 ;;
      --group-name) TOPFLOW_GROUP_NAME="$2"; shift 2 ;;
      --sni) TOPFLOW_SNI="$2"; shift 2 ;;
      --max-connections) TOPFLOW_MAX_CONNECTIONS="$2"; shift 2 ;;
      --download-url) TOPFLOW_DOWNLOAD_URL="$2"; shift 2 ;;
      --ca-cert) TOPFLOW_CA_CERT="$2"; shift 2 ;;
      --ca-key) TOPFLOW_CA_KEY="$2"; shift 2 ;;
      --generate-ca) TOPFLOW_GENERATE_CA="true"; shift ;;
      --debug|-d) TOPFLOW_DEBUG="true"; shift ;;
      --skip-cert-verify) TOPFLOW_SKIP_CERT_VERIFY="true"; shift ;;
      --no-firewall) TOPFLOW_OPEN_FIREWALL="false"; shift ;;
      --user) TOPFLOW_USER="$2"; shift 2 ;;
      --group) TOPFLOW_GROUP="$2"; shift 2 ;;
      --service-name) SERVICE_NAME="$2"; shift 2 ;;
      --install-dir) INSTALL_DIR="$2"; shift 2 ;;
      --etc-dir) ETC_DIR="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "install 未知参数：$1" ;;
    esac
  done
  refresh_paths
}

parse_update_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --download-url) TOPFLOW_DOWNLOAD_URL="$2"; shift 2 ;;
      --service-name) SERVICE_NAME="$2"; shift 2 ;;
      --install-dir) INSTALL_DIR="$2"; shift 2 ;;
      --etc-dir) ETC_DIR="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "update 未知参数：$1" ;;
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
      *) die "uninstall 未知参数：$1" ;;
    esac
  done
  refresh_paths
}

install_dependencies() {
  log "安装运行依赖..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl tar gzip openssl qrencode python3 coreutils libcap2-bin >/dev/null
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ca-certificates curl tar gzip openssl qrencode python3 coreutils shadow-utils libcap >/dev/null
  elif command -v yum >/dev/null 2>&1; then
    yum install -y ca-certificates curl tar gzip openssl qrencode python3 coreutils shadow-utils libcap >/dev/null
  else
    die "暂不支持当前发行版的软件包管理器，请手动安装 curl / openssl / qrencode / python3 / systemd / setcap。"
  fi
}

ensure_runtime_user() {
  if ! getent group "$TOPFLOW_GROUP" >/dev/null 2>&1; then
    groupadd --system "$TOPFLOW_GROUP"
  fi

  if ! id "$TOPFLOW_USER" >/dev/null 2>&1; then
    local no_login_shell="/usr/sbin/nologin"
    [[ -x "$no_login_shell" ]] || no_login_shell="/sbin/nologin"
    [[ -x "$no_login_shell" ]] || no_login_shell="/bin/false"
    useradd --system --gid "$TOPFLOW_GROUP" --home-dir "$INSTALL_DIR" --create-home --shell "$no_login_shell" "$TOPFLOW_USER"
  fi
}

ensure_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)
      ;;
    aarch64|arm64)
      if [[ "$TOPFLOW_DOWNLOAD_URL" == "$DEFAULT_DOWNLOAD_URL" ]]; then
        die "当前默认下载地址只适合 x86_64。ARM 服务器请通过 --download-url 指定 ARM 二进制地址。"
      fi
      ;;
    *)
      if [[ "$TOPFLOW_DOWNLOAD_URL" == "$DEFAULT_DOWNLOAD_URL" ]]; then
        die "当前架构 ${arch} 未提供默认二进制，请通过 --download-url 指定对应架构文件。"
      fi
      ;;
  esac
}

generate_or_validate_psk() {
  if [[ -z "$TOPFLOW_PSK" ]]; then
    TOPFLOW_PSK="$(openssl rand -base64 32 | tr -d '\r\n')"
    log "未提供 PSK，已自动生成。"
  fi

  local decoded_len
  decoded_len="$(printf '%s' "$TOPFLOW_PSK" | base64 -d 2>/dev/null | wc -c | tr -d ' ')"
  [[ "$decoded_len" == "32" ]] || die "PSK 必须是 Base64 编码，且解码后必须为 32 字节。"
}

load_env_if_exists() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi
}

download_binary_to_temp() {
  local tmp_file
  tmp_file="$(mktemp)"
  curl -fsSL "$TOPFLOW_DOWNLOAD_URL" -o "$tmp_file"
  if head -n 5 "$tmp_file" | grep -q 'git-lfs.github.com/spec'; then
    rm -f "$tmp_file"
    die "下载到的是 Git LFS 指针文件，不是真实二进制。"
  fi
  chmod 0755 "$tmp_file"
  printf '%s' "$tmp_file"
}

install_binary() {
  log "下载服务端二进制：$TOPFLOW_DOWNLOAD_URL"
  mkdir -p "$INSTALL_DIR" "$ETC_DIR"
  local tmp_file
  tmp_file="$(download_binary_to_temp)"
  trap 'rm -f "${tmp_file:-}"' RETURN
  install -m 0755 "$tmp_file" "$BIN_PATH"
  chown root:"$TOPFLOW_GROUP" "$BIN_PATH"
  if ! "$BIN_PATH" --help >/dev/null 2>&1; then
    warn "二进制自检未通过，可能是架构不匹配；如启动失败请检查下载地址。"
  fi
}

configure_binary_bind_capability() {
  local listen_port
  parse_host_port "$TOPFLOW_LISTEN"
  listen_port="$PARSED_PORT"

  if [[ ! "$listen_port" =~ ^[0-9]+$ ]]; then
    warn "无法从 listen 地址中识别端口：$TOPFLOW_LISTEN，已跳过端口能力配置。"
    return 0
  fi

  if (( listen_port < 1024 )); then
    command -v setcap >/dev/null 2>&1 || die "监听端口 ${listen_port} 需要 setcap，但系统未安装该命令。"
    log "检测到特权端口 ${listen_port}，为服务端二进制授予 cap_net_bind_service"
    setcap 'cap_net_bind_service=+ep' "$BIN_PATH" || die "为 ${BIN_PATH} 设置 cap_net_bind_service 失败。"
    return 0
  fi

  if command -v setcap >/dev/null 2>&1; then
    setcap -r "$BIN_PATH" >/dev/null 2>&1 || true
  fi
}

write_env_file() {
  log "写入服务配置：$ENV_FILE"
  cat > "$ENV_FILE" <<EOF
TOPFLOW_LISTEN='$(escape_single_quotes "$TOPFLOW_LISTEN")'
TOPFLOW_PUBLIC_ENDPOINT='$(escape_single_quotes "$TOPFLOW_PUBLIC_ENDPOINT")'
TOPFLOW_NODE_NAME='$(escape_single_quotes "$TOPFLOW_NODE_NAME")'
TOPFLOW_GROUP_NAME='$(escape_single_quotes "$TOPFLOW_GROUP_NAME")'
TOPFLOW_SNI='$(escape_single_quotes "$TOPFLOW_SNI")'
TOPFLOW_PSK='$(escape_single_quotes "$TOPFLOW_PSK")'
TOPFLOW_MAX_CONNECTIONS='$(escape_single_quotes "$TOPFLOW_MAX_CONNECTIONS")'
TOPFLOW_SKIP_CERT_VERIFY='$(escape_single_quotes "$TOPFLOW_SKIP_CERT_VERIFY")'
TOPFLOW_DEBUG='$(escape_single_quotes "$TOPFLOW_DEBUG")'
TOPFLOW_CA_CERT='$(escape_single_quotes "$TOPFLOW_CA_CERT")'
TOPFLOW_CA_KEY='$(escape_single_quotes "$TOPFLOW_CA_KEY")'
TOPFLOW_GENERATE_CA='$(escape_single_quotes "$TOPFLOW_GENERATE_CA")'
TOPFLOW_EXTRA_ARGS='$(escape_single_quotes "$TOPFLOW_EXTRA_ARGS")'
TOPFLOW_DOWNLOAD_URL='$(escape_single_quotes "$TOPFLOW_DOWNLOAD_URL")'
EOF
  chown root:"$TOPFLOW_GROUP" "$ENV_FILE"
  chmod 0640 "$ENV_FILE"
}

write_runner() {
  log "生成启动包装脚本：$RUNNER_PATH"
  cat > "$RUNNER_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$ENV_FILE"
BIN_PATH="$BIN_PATH"

if [[ ! -f "\$ENV_FILE" ]]; then
  echo "TopFlow env file not found: \$ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "\$ENV_FILE"

args=(--listen "\${TOPFLOW_LISTEN:-0.0.0.0:8888}" --max-connections "\${TOPFLOW_MAX_CONNECTIONS:-10000}")

if [[ -n "\${TOPFLOW_PSK:-}" ]]; then
  args+=(--psk "\$TOPFLOW_PSK")
fi
if [[ -n "\${TOPFLOW_CA_CERT:-}" ]]; then
  args+=(--ca-cert "\$TOPFLOW_CA_CERT")
fi
if [[ -n "\${TOPFLOW_CA_KEY:-}" ]]; then
  args+=(--ca-key "\$TOPFLOW_CA_KEY")
fi
if [[ "\${TOPFLOW_GENERATE_CA:-false}" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  args+=(--generate-ca)
fi
if [[ "\${TOPFLOW_SKIP_CERT_VERIFY:-true}" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  args+=(--skip-cert-verify)
fi
if [[ "\${TOPFLOW_DEBUG:-false}" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  args+=(--debug)
fi
if [[ -n "\${TOPFLOW_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra_args=(\${TOPFLOW_EXTRA_ARGS})
  args+=("\${extra_args[@]}")
fi

exec "\$BIN_PATH" "\${args[@]}"
EOF
  chmod 0750 "$RUNNER_PATH"
  chown root:"$TOPFLOW_GROUP" "$RUNNER_PATH"
}

write_systemd_unit() {
  log "注册 systemd 服务：$SERVICE_NAME"
  local extra_caps=""
  if listen_port_requires_privileged_bind; then
    extra_caps=$'AmbientCapabilities=CAP_NET_BIND_SERVICE\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE'
  fi
  cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=TopFlow HeadBridge Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$TOPFLOW_USER
Group=$TOPFLOW_GROUP
WorkingDirectory=$INSTALL_DIR
ExecStart=$RUNNER_PATH
Restart=always
RestartSec=2
LimitNOFILE=1048576
NoNewPrivileges=true
${extra_caps}

[Install]
WantedBy=multi-user.target
EOF
}

configure_firewall_add() {
  is_true "$TOPFLOW_OPEN_FIREWALL" || return 0
  local port="${TOPFLOW_LISTEN##*:}"
  [[ "$port" =~ ^[0-9]+$ ]] || {
    warn "无法从 listen 地址中自动识别端口：$TOPFLOW_LISTEN，已跳过防火墙放行。"
    return 0
  }

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi 'Status: active'; then
    log "检测到 UFW，自动放行 ${port}/tcp"
    ufw allow "${port}/tcp" >/dev/null || warn "UFW 放行失败，请手动执行：ufw allow ${port}/tcp"
    return 0
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    log "检测到 firewalld，自动放行 ${port}/tcp"
    firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null || warn "firewalld 放行失败，请手动执行：firewall-cmd --permanent --add-port=${port}/tcp"
    firewall-cmd --reload >/dev/null || true
    return 0
  fi
  warn "未检测到活动的 UFW / firewalld，已跳过防火墙配置。"
}

configure_firewall_remove() {
  local listen_value="${TOPFLOW_LISTEN:-}"
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
  log "启动并设置开机自启..."
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null
  systemctl restart "$SERVICE_NAME"
  sleep 1
  systemctl --no-pager --full status "$SERVICE_NAME" || {
    journalctl -u "$SERVICE_NAME" -n 80 --no-pager || true
    die "服务启动失败，请检查上面的日志。"
  }
}

check_current_install() {
  [[ -f "$BIN_PATH" ]] || die "未找到服务端二进制：$BIN_PATH"
  systemctl cat "$SERVICE_NAME" >/dev/null 2>&1 || die "未找到 systemd 服务：$SERVICE_NAME"
}

detect_public_endpoint() {
  local listen_host listen_port public_host
  parse_host_port "$TOPFLOW_LISTEN"
  listen_host="$PARSED_HOST"
  listen_port="$PARSED_PORT"

  if [[ -n "${TOPFLOW_PUBLIC_ENDPOINT:-}" ]]; then
    parse_host_port "$TOPFLOW_PUBLIC_ENDPOINT" "$listen_port"
    printf '%s' "$(format_endpoint "$PARSED_HOST" "$PARSED_PORT")"
    return 0
  fi

  if ! is_wildcard_host "$listen_host"; then
    printf '%s' "$(format_endpoint "$listen_host" "$listen_port")"
    return 0
  fi

  if [[ "$listen_host" == "::" ]]; then
    public_host="$(curl -6fsSL --max-time 5 https://api64.ipify.org 2>/dev/null || true)"
    if [[ -z "$public_host" ]]; then
      public_host="$(curl -6fsSL --max-time 5 https://ipv6.icanhazip.com 2>/dev/null | tr -d '\r\n' || true)"
    fi
    if [[ -n "$public_host" ]]; then
      printf '%s' "$(format_endpoint "$public_host" "$listen_port")"
      return 0
    fi
  fi

  public_host="$(curl -4fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$public_host" ]]; then
    public_host="$(curl -4fsSL --max-time 5 https://ipv4.icanhazip.com 2>/dev/null | tr -d '\r\n' || true)"
  fi

  if [[ -n "$public_host" ]]; then
    printf '%s' "$(format_endpoint "$public_host" "$listen_port")"
    return 0
  fi

  printf '%s' "$(format_endpoint "REPLACE_WITH_PUBLIC_HOST" "$listen_port")"
}

build_topflow_share_json() {
  local endpoint="$1"
  local host port insecure_tls
  parse_host_port "$endpoint"
  host="$PARSED_HOST"
  port="$PARSED_PORT"

  if is_true "$TOPFLOW_SKIP_CERT_VERIFY"; then
    insecure_tls="true"
  else
    insecure_tls="false"
  fi

  TOPFLOW_SHARE_HOST="$host" \
  TOPFLOW_SHARE_PORT="$port" \
  TOPFLOW_SHARE_NODE_NAME="$TOPFLOW_NODE_NAME" \
  TOPFLOW_SHARE_GROUP_NAME="$TOPFLOW_GROUP_NAME" \
  TOPFLOW_SHARE_SNI="$TOPFLOW_SNI" \
  TOPFLOW_SHARE_PSK="$TOPFLOW_PSK" \
  TOPFLOW_SHARE_INSECURE_TLS="$insecure_tls" \
  python3 <<'PY'
import json
import os
import uuid

host = os.environ["TOPFLOW_SHARE_HOST"]
port = int(os.environ["TOPFLOW_SHARE_PORT"])
node_name = os.environ["TOPFLOW_SHARE_NODE_NAME"]
group_name = os.environ["TOPFLOW_SHARE_GROUP_NAME"]
sni = os.environ["TOPFLOW_SHARE_SNI"]
psk = os.environ["TOPFLOW_SHARE_PSK"]
insecure_tls = os.environ["TOPFLOW_SHARE_INSECURE_TLS"].lower() == "true"

share = {
    "app": "TopFlow",
    "format": "topflow-share",
    "formatVersion": 1,
    "activeIndex": 0,
    "nodes": [
        {
            "id": uuid.uuid4().hex,
            "name": node_name,
            "host": host,
            "group": group_name,
            "port": port,
            "sni": sni,
            "insecureTls": insecure_tls,
            "pskB64": psk,
            "kernelType": "HeadBridge"
        }
    ]
}

print(json.dumps(share, ensure_ascii=False, separators=(",", ":")))
PY
}

build_topflow_link() {
  local endpoint="$1"
  local share_json
  share_json="$(build_topflow_share_json "$endpoint")"

  TOPFLOW_SHARE_JSON="$share_json" python3 <<'PY'
import base64
import os
import zlib

data = os.environ["TOPFLOW_SHARE_JSON"].encode("utf-8")
compressed = zlib.compress(data, 9)
raw_deflate = compressed[2:-4]
encoded = base64.urlsafe_b64encode(raw_deflate).decode("ascii").rstrip("=")
print(f"topflow://import?zip=deflate&data={encoded}")
PY
}

print_qr() {
  local text="$1"
  if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ANSIUTF8 "$text" || warn "二维码生成失败，请手动复制上面的链接。"
  else
    warn "未安装 qrencode，无法输出二维码。"
  fi
}

print_connection_summary() {
  local endpoint host port link script_path
  endpoint="$(detect_public_endpoint)"
  parse_host_port "$endpoint"
  host="$PARSED_HOST"
  port="$PARSED_PORT"
  link="$(build_topflow_link "$endpoint")"
  script_path="$(resolve_path "$0")"

  cat <<EOF

TopFlow 服务端部署完成。

服务名称:      $SERVICE_NAME
监听地址:      $TOPFLOW_LISTEN
客户端地址:    $endpoint
节点名称:      $TOPFLOW_NODE_NAME
分组名称:      $TOPFLOW_GROUP_NAME
SNI:           $TOPFLOW_SNI
PSK:           $TOPFLOW_PSK
二进制路径:    $BIN_PATH
配置文件:      $ENV_FILE
统一脚本:      $script_path

客户端配置清单:
  host        = $host
  port        = $port
  sni         = $TOPFLOW_SNI
  insecureTls = $TOPFLOW_SKIP_CERT_VERIFY
  pskB64      = $TOPFLOW_PSK
  kernelType  = HeadBridge

可复制导入链接:
$link

终端二维码:
EOF

  print_qr "$link"

  cat <<EOF

常用命令:
  systemctl status $SERVICE_NAME --no-pager
  systemctl restart $SERVICE_NAME
  journalctl -u $SERVICE_NAME -f
  sudo bash $script_path update
  sudo bash $script_path uninstall --yes
EOF

  if [[ "$host" == "REPLACE_WITH_PUBLIC_HOST" ]]; then
    warn "未能自动探测公网地址，请改用 --public-endpoint your.domain.com:${port} 或 --public-endpoint [你的IPv6]:${port} 重新安装，或手动把导入链接里的地址改成真实公网 IP/域名。"
  fi
}

update_server() {
  require_root
  ensure_systemd
  local args=("$@")
  parse_update_args "${args[@]}"
  load_env_if_exists
  parse_update_args "${args[@]}"
  check_current_install

  log "下载更新：$TOPFLOW_DOWNLOAD_URL"
  local new_bin
  new_bin="$(download_binary_to_temp)"
  trap 'rm -f "${new_bin:-}"' EXIT

  "$new_bin" --help >/dev/null 2>&1 || die "下载后的新二进制无法执行 --help，自检失败。"

  local backup_path="${BIN_PATH}.bak.$(date +%Y%m%d-%H%M%S)"
  cp -f "$BIN_PATH" "$backup_path"
  install -m 0755 "$new_bin" "$BIN_PATH"
  configure_binary_bind_capability

  if systemctl restart "$SERVICE_NAME"; then
    systemctl --no-pager --full status "$SERVICE_NAME" || true
    log "更新完成。备份文件：$backup_path"
    return 0
  fi

  log "新版本启动失败，正在回滚旧版本..."
  install -m 0755 "$backup_path" "$BIN_PATH"
  configure_binary_bind_capability
  systemctl restart "$SERVICE_NAME" || true
  journalctl -u "$SERVICE_NAME" -n 80 --no-pager || true
  die "更新失败，已尝试回滚到旧版本。"
}

confirm_uninstall() {
  if is_true "$ASSUME_YES"; then
    return 0
  fi
  printf "确认卸载 TopFlow 服务端？这将停止并删除 systemd 服务、安装目录%s [y/N]: " "$(is_true "$KEEP_CONFIG" && printf '，保留配置目录' || printf '与配置目录')"
  read -r answer
  case "$(lower "$answer")" in
    y|yes) ;;
    *) die "已取消卸载。" ;;
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
    if id "$TOPFLOW_USER" >/dev/null 2>&1; then
      userdel "$TOPFLOW_USER" >/dev/null 2>&1 || warn "删除用户 $TOPFLOW_USER 失败，可手动处理。"
    fi
    if getent group "$TOPFLOW_GROUP" >/dev/null 2>&1; then
      groupdel "$TOPFLOW_GROUP" >/dev/null 2>&1 || warn "删除用户组 $TOPFLOW_GROUP 失败，可手动处理。"
    fi
  fi

  log "TopFlow 服务端已卸载完成。"
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
  configure_binary_bind_capability
  write_env_file
  write_runner
  write_systemd_unit
  configure_firewall_add
  enable_and_start_service
  print_connection_summary
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
    *) die "未知子命令：$command" ;;
  esac
}

main "$@"
