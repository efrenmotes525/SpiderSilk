#!/bin/sh
set -eu

SCRIPT_NAME=$(basename "$0")
APP_NAME="socks5-proxy"
SERVICE_NAME_DEFAULT="socks5-proxy"
INSTALL_DIR_DEFAULT="/opt/socks5-proxy"
ETC_DIR_DEFAULT="/etc/socks5-proxy"
LOG_DIR_DEFAULT="/var/log/socks5-proxy"
RUN_USER_DEFAULT="socks5proxy"
RUN_GROUP_DEFAULT="socks5proxy"

RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
BLUE=$(printf '\033[0;34m')
CYAN=$(printf '\033[0;36m')
NC=$(printf '\033[0m')

COMMAND="install"
SOCKS5_PORT="${SOCKS5_PORT:-1080}"
SOCKS5_USERNAME="${SOCKS5_USERNAME:-}"
SOCKS5_PASSWORD="${SOCKS5_PASSWORD:-}"
PUBLIC_IPV4="${PUBLIC_IPV4:-}"
PUBLIC_IPV6="${PUBLIC_IPV6:-}"
SERVICE_NAME="${SERVICE_NAME:-$SERVICE_NAME_DEFAULT}"
INSTALL_DIR="${INSTALL_DIR:-$INSTALL_DIR_DEFAULT}"
ETC_DIR="${ETC_DIR:-$ETC_DIR_DEFAULT}"
LOG_DIR="${LOG_DIR:-$LOG_DIR_DEFAULT}"
RUN_USER="${RUN_USER:-$RUN_USER_DEFAULT}"
RUN_GROUP="${RUN_GROUP:-$RUN_GROUP_DEFAULT}"
NO_FIREWALL="${NO_FIREWALL:-false}"
ASSUME_YES="${ASSUME_YES:-false}"
AUTO_GENERATE_CREDS="${AUTO_GENERATE_CREDS:-true}"
FORCE_IPV4="${FORCE_IPV4:-false}"
FORCE_IPV6="${FORCE_IPV6:-false}"
DISABLE_IPV4="${DISABLE_IPV4:-false}"
DISABLE_IPV6="${DISABLE_IPV6:-false}"

OS_FAMILY=""
PKG_MANAGER=""
INIT_SYSTEM=""
SYSTEMD_UNIT=""
OPENRC_SERVICE=""
PYTHON_BIN=""
CONFIG_PATH=""
SERVER_PATH=""
RUNNER_PATH=""
STATE_PATH=""
HAS_IPV4="false"
HAS_IPV6="false"
LISTEN_IPV4="false"
LISTEN_IPV6="false"
DETECTED_IPV4=""
DETECTED_IPV6=""

log() {
  printf '%s[%s]%s %s\n' "$CYAN" "$APP_NAME" "$NC" "$*"
}

success() {
  printf '%s[%s]%s %s\n' "$GREEN" "$APP_NAME" "$NC" "$*"
}

warn() {
  printf '%s[%s]%s %s\n' "$YELLOW" "$APP_NAME" "$NC" "$*" >&2
}

die() {
  printf '%s[%s]%s %s\n' "$RED" "$APP_NAME" "$NC" "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Portable SOCKS5 installer

Usage:
  sh $SCRIPT_NAME [install] [options]
  sh $SCRIPT_NAME uninstall [options]
  sh $SCRIPT_NAME status
  sh $SCRIPT_NAME restart

Install options:
  --port <1-65535>           SOCKS5 port, default: 1080
  --username <name>          username; auto-generated when omitted
  --password <pass>          password; auto-generated when omitted
  --public-ipv4 <ip>         override detected public IPv4
  --public-ipv6 <ip>         override detected public IPv6
  --service-name <name>      default: $SERVICE_NAME_DEFAULT
  --install-dir <dir>        default: $INSTALL_DIR_DEFAULT
  --etc-dir <dir>            default: $ETC_DIR_DEFAULT
  --log-dir <dir>            default: $LOG_DIR_DEFAULT
  --run-user <name>          default: $RUN_USER_DEFAULT
  --run-group <name>         default: $RUN_GROUP_DEFAULT
  --ipv4-only                listen on IPv4 only
  --ipv6-only                listen on IPv6 only
  --no-firewall              do not modify UFW or firewalld
  --no-auto-creds            require explicit username/password
  --yes                      non-interactive install/uninstall
  -h, --help                 show this help

Examples:
  curl -fsSL https://example.com/install_socks5_proxy.sh -o /tmp/install_socks5_proxy.sh
  sh /tmp/install_socks5_proxy.sh --port 2080
  wget -qO- https://example.com/install_socks5_proxy.sh | sh -s -- --ipv4-only
EOF
}

refresh_paths() {
  SYSTEMD_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
  OPENRC_SERVICE="/etc/init.d/${SERVICE_NAME}"
  CONFIG_PATH="${ETC_DIR}/config.json"
  STATE_PATH="${ETC_DIR}/install-state.env"
  SERVER_PATH="${INSTALL_DIR}/socks5_server.py"
  RUNNER_PATH="${INSTALL_DIR}/run-socks5-proxy.sh"
}

refresh_paths

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_true() {
  case "$(lower "${1:-false}")" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

group_exists() {
  if command_exists getent; then
    getent group "$1" >/dev/null 2>&1
  else
    grep -q "^$1:" /etc/group 2>/dev/null
  fi
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "please run this script as root"
}

resolve_python() {
  if command_exists python3; then
    PYTHON_BIN=$(command -v python3)
  elif command_exists python; then
    PYTHON_BIN=$(command -v python)
  else
    die "python3 is required"
  fi
}

is_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

validate_port() {
  is_integer "$SOCKS5_PORT" || die "port must be a number"
  [ "$SOCKS5_PORT" -ge 1 ] && [ "$SOCKS5_PORT" -le 65535 ] || die "port must be between 1 and 65535"
}

random_hex() {
  openssl rand -hex "$1" 2>/dev/null
}

validate_credentials() {
  if is_true "$AUTO_GENERATE_CREDS"; then
    if [ -z "$SOCKS5_USERNAME" ]; then
      SOCKS5_USERNAME="user$(random_hex 4)"
    fi
    if [ -z "$SOCKS5_PASSWORD" ]; then
      SOCKS5_PASSWORD="pass$(random_hex 8)"
    fi
  fi

  [ -n "$SOCKS5_USERNAME" ] || die "username is required"
  [ -n "$SOCKS5_PASSWORD" ] || die "password is required"
  [ "$(printf '%s' "$SOCKS5_USERNAME" | wc -c | tr -d ' ')" -le 128 ] || die "username is too long"
  [ "$(printf '%s' "$SOCKS5_PASSWORD" | wc -c | tr -d ' ')" -le 256 ] || die "password is too long"
}

need_value() {
  [ "$#" -ge 2 ] || die "option $1 requires a value"
}

parse_args() {
  if [ "$#" -gt 0 ]; then
    case "$1" in
      install|uninstall|status|restart)
        COMMAND="$1"
        shift
        ;;
    esac
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --port)
        need_value "$@"
        SOCKS5_PORT="$2"
        shift 2
        ;;
      --username)
        need_value "$@"
        SOCKS5_USERNAME="$2"
        shift 2
        ;;
      --password)
        need_value "$@"
        SOCKS5_PASSWORD="$2"
        shift 2
        ;;
      --public-ipv4)
        need_value "$@"
        PUBLIC_IPV4="$2"
        shift 2
        ;;
      --public-ipv6)
        need_value "$@"
        PUBLIC_IPV6="$2"
        shift 2
        ;;
      --service-name)
        need_value "$@"
        SERVICE_NAME="$2"
        shift 2
        ;;
      --install-dir)
        need_value "$@"
        INSTALL_DIR="$2"
        shift 2
        ;;
      --etc-dir)
        need_value "$@"
        ETC_DIR="$2"
        shift 2
        ;;
      --log-dir)
        need_value "$@"
        LOG_DIR="$2"
        shift 2
        ;;
      --run-user)
        need_value "$@"
        RUN_USER="$2"
        shift 2
        ;;
      --run-group)
        need_value "$@"
        RUN_GROUP="$2"
        shift 2
        ;;
      --ipv4-only)
        FORCE_IPV4="true"
        DISABLE_IPV6="true"
        shift
        ;;
      --ipv6-only)
        FORCE_IPV6="true"
        DISABLE_IPV4="true"
        shift
        ;;
      --no-firewall)
        NO_FIREWALL="true"
        shift
        ;;
      --no-auto-creds)
        AUTO_GENERATE_CREDS="false"
        shift
        ;;
      --yes)
        ASSUME_YES="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done

  refresh_paths
}

detect_os() {
  [ -f /etc/os-release ] || die "/etc/os-release not found"
  # shellcheck disable=SC1091
  . /etc/os-release

  if command_exists apt-get; then
    OS_FAMILY="debian"
    PKG_MANAGER="apt"
  elif command_exists dnf; then
    OS_FAMILY="rhel"
    PKG_MANAGER="dnf"
  elif command_exists yum; then
    OS_FAMILY="rhel"
    PKG_MANAGER="yum"
  elif command_exists apk; then
    OS_FAMILY="alpine"
    PKG_MANAGER="apk"
  else
    die "unsupported package manager; expected apt, dnf, yum, or apk"
  fi

  if command_exists systemctl && [ -d /run/systemd/system ]; then
    INIT_SYSTEM="systemd"
  elif command_exists rc-service && command_exists rc-update; then
    INIT_SYSTEM="openrc"
  else
    die "unsupported init system; expected systemd or OpenRC"
  fi

  log "detected distro: ${PRETTY_NAME:-unknown}"
  log "package manager: $PKG_MANAGER"
  log "init system: $INIT_SYSTEM"
}

install_packages() {
  log "installing runtime dependencies"
  case "$PKG_MANAGER" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y ca-certificates curl openssl python3 iproute2
      ;;
    dnf)
      dnf install -y ca-certificates curl openssl python3 iproute
      ;;
    yum)
      yum install -y ca-certificates curl openssl python3 iproute
      ;;
    apk)
      apk add --no-cache ca-certificates curl openssl python3 iproute2
      update-ca-certificates >/dev/null 2>&1 || true
      ;;
  esac
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
  ip="${1:-}"
  [ -n "$ip" ] || return 1
  case "$ip" in
    *:*) ;;
    *) return 1 ;;
  esac
  ip=$(lower "$ip")
  case "$ip" in
    ::|::1|fc*|fd*|fe8*|fe9*|fea*|feb*|2001:db8*) return 1 ;;
  esac
  return 0
}

detect_public_ipv4() {
  if [ -n "$PUBLIC_IPV4" ]; then
    printf '%s' "$PUBLIC_IPV4"
    return 0
  fi

  if command_exists ip; then
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([^ ]*\).*/\1/p' | head -n 1 || true)
    if is_public_ipv4 "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
  fi

  for url in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip
  do
    ip=$(curl -4 -fsS --max-time 5 "$url" 2>/dev/null | tr -d '\r\n' || true)
    if is_public_ipv4 "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
  done
}

detect_public_ipv6() {
  if [ -n "$PUBLIC_IPV6" ]; then
    printf '%s' "$PUBLIC_IPV6"
    return 0
  fi

  if command_exists ip; then
    ip=$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | sed -n 's/.* src \([^ ]*\).*/\1/p' | head -n 1 || true)
    if is_public_ipv6 "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
  fi

  for url in https://api64.ipify.org https://ipv6.icanhazip.com
  do
    ip=$(curl -6 -fsS --max-time 5 "$url" 2>/dev/null | tr -d '\r\n' || true)
    if is_public_ipv6 "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
  done
}

detect_network() {
  DETECTED_IPV4=$(detect_public_ipv4 || true)
  DETECTED_IPV6=$(detect_public_ipv6 || true)

  if is_public_ipv4 "$DETECTED_IPV4"; then
    HAS_IPV4="true"
  else
    HAS_IPV4="false"
    DETECTED_IPV4=""
  fi

  if is_public_ipv6 "$DETECTED_IPV6"; then
    HAS_IPV6="true"
  else
    HAS_IPV6="false"
    DETECTED_IPV6=""
  fi

  LISTEN_IPV4="$HAS_IPV4"
  LISTEN_IPV6="$HAS_IPV6"

  is_true "$FORCE_IPV4" && LISTEN_IPV4="true"
  is_true "$FORCE_IPV6" && LISTEN_IPV6="true"
  is_true "$DISABLE_IPV4" && LISTEN_IPV4="false"
  is_true "$DISABLE_IPV6" && LISTEN_IPV6="false"

  if ! is_true "$LISTEN_IPV4" && ! is_true "$LISTEN_IPV6"; then
    die "no usable network stack detected; use --public-ipv4/--public-ipv6 or adjust flags"
  fi

  log "public IPv4: ${DETECTED_IPV4:-not available}"
  log "public IPv6: ${DETECTED_IPV6:-not available}"
  log "listen IPv4: $LISTEN_IPV4"
  log "listen IPv6: $LISTEN_IPV6"
}

ensure_group() {
  if group_exists "$RUN_GROUP"; then
    return 0
  fi

  case "$OS_FAMILY" in
    alpine) addgroup -S "$RUN_GROUP" >/dev/null ;;
    *) groupadd --system "$RUN_GROUP" >/dev/null ;;
  esac
}

ensure_user() {
  if id "$RUN_USER" >/dev/null 2>&1; then
    return 0
  fi

  case "$OS_FAMILY" in
    alpine)
      adduser -S -D -H -h "$INSTALL_DIR" -s /sbin/nologin -G "$RUN_GROUP" "$RUN_USER" >/dev/null
      ;;
    *)
      useradd --system --home-dir "$INSTALL_DIR" --shell /usr/sbin/nologin --gid "$RUN_GROUP" "$RUN_USER" >/dev/null 2>&1 \
        || useradd --system --home-dir "$INSTALL_DIR" --shell /sbin/nologin --gid "$RUN_GROUP" "$RUN_USER" >/dev/null
      ;;
  esac
}

create_runtime_layout() {
  mkdir -p "$INSTALL_DIR" "$ETC_DIR" "$LOG_DIR"
  ensure_group
  ensure_user
  chown -R root:root "$INSTALL_DIR" "$ETC_DIR"
  chown -R "$RUN_USER:$RUN_GROUP" "$LOG_DIR"
  chmod 0755 "$INSTALL_DIR" "$ETC_DIR"
  chmod 0750 "$LOG_DIR"
}

write_server() {
  mkdir -p "$INSTALL_DIR"
  cat > "$SERVER_PATH" <<'PY'
#!/usr/bin/env python3
import argparse
import asyncio
import json
import logging
from logging.handlers import RotatingFileHandler
import signal
import socket
import struct
import sys
from contextlib import suppress


LOGGER = logging.getLogger("socks5_proxy")


def setup_logging(log_file: str) -> None:
    LOGGER.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    handlers = [logging.StreamHandler(sys.stdout)]
    if log_file:
        handlers.append(RotatingFileHandler(log_file, maxBytes=5 * 1024 * 1024, backupCount=3))
    for handler in handlers:
        handler.setFormatter(formatter)
        LOGGER.addHandler(handler)


def is_ipv6_literal(host: str) -> bool:
    with suppress(ValueError):
        socket.inet_pton(socket.AF_INET6, host)
        return True
    return False


def build_reply(rep: int, local_addr=None) -> bytes:
    if not local_addr:
        return b"\x05" + bytes([rep]) + b"\x00\x01\x00\x00\x00\x00\x00\x00"

    host = local_addr[0]
    port = local_addr[1]
    try:
        if is_ipv6_literal(host):
            packed = socket.inet_pton(socket.AF_INET6, host)
            return b"\x05" + bytes([rep]) + b"\x00\x04" + packed + struct.pack(">H", port)
        packed = socket.inet_aton(host)
        return b"\x05" + bytes([rep]) + b"\x00\x01" + packed + struct.pack(">H", port)
    except OSError:
        return b"\x05" + bytes([rep]) + b"\x00\x01\x00\x00\x00\x00\x00\x00"


class Socks5Server:
    def __init__(self, config: dict):
        self.config = config
        self.servers = []

    async def read_exact(self, reader: asyncio.StreamReader, size: int) -> bytes:
        return await reader.readexactly(size)

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        peer = writer.get_extra_info("peername")
        try:
            LOGGER.info("accepted connection from %s", peer)
            if not await self.handle_handshake(reader, writer):
                return
            if self.config["username"]:
                if not await self.handle_auth(reader, writer):
                    return
            await self.handle_request(reader, writer)
        except asyncio.IncompleteReadError:
            LOGGER.debug("client closed early: %s", peer)
        except Exception as exc:
            LOGGER.exception("client handling failed for %s: %s", peer, exc)
        finally:
            writer.close()
            with suppress(Exception):
                await writer.wait_closed()

    async def handle_handshake(self, reader, writer) -> bool:
        data = await self.read_exact(reader, 2)
        version, method_count = data[0], data[1]
        if version != 0x05:
            return False
        methods = await self.read_exact(reader, method_count)
        need_auth = bool(self.config["username"])
        if need_auth and 0x02 in methods:
            writer.write(b"\x05\x02")
        elif not need_auth and 0x00 in methods:
            writer.write(b"\x05\x00")
        else:
            writer.write(b"\x05\xff")
            await writer.drain()
            return False
        await writer.drain()
        return True

    async def handle_auth(self, reader, writer) -> bool:
        version = await self.read_exact(reader, 1)
        if version[0] != 0x01:
            writer.write(b"\x01\x01")
            await writer.drain()
            return False
        username_len = (await self.read_exact(reader, 1))[0]
        username = (await self.read_exact(reader, username_len)).decode("utf-8", errors="ignore")
        password_len = (await self.read_exact(reader, 1))[0]
        password = (await self.read_exact(reader, password_len)).decode("utf-8", errors="ignore")
        if username == self.config["username"] and password == self.config["password"]:
            writer.write(b"\x01\x00")
            await writer.drain()
            return True
        writer.write(b"\x01\x01")
        await writer.drain()
        return False

    async def handle_request(self, reader, writer) -> None:
        header = await self.read_exact(reader, 4)
        version, command, _, atyp = header
        if version != 0x05:
            return
        if command != 0x01:
            writer.write(build_reply(0x07))
            await writer.drain()
            return

        if atyp == 0x01:
            address = socket.inet_ntoa(await self.read_exact(reader, 4))
        elif atyp == 0x03:
            size = (await self.read_exact(reader, 1))[0]
            address = (await self.read_exact(reader, size)).decode("utf-8", errors="ignore")
        elif atyp == 0x04:
            address = socket.inet_ntop(socket.AF_INET6, await self.read_exact(reader, 16))
        else:
            writer.write(build_reply(0x08))
            await writer.drain()
            return

        port = struct.unpack(">H", await self.read_exact(reader, 2))[0]
        LOGGER.info("connecting to %s:%s", address, port)

        try:
            target_reader, target_writer = await asyncio.wait_for(
                asyncio.open_connection(address, port),
                timeout=self.config["connect_timeout"],
            )
        except asyncio.TimeoutError:
            writer.write(build_reply(0x04))
            await writer.drain()
            return
        except OSError:
            writer.write(build_reply(0x05))
            await writer.drain()
            return

        writer.write(build_reply(0x00, target_writer.get_extra_info("sockname")))
        await writer.drain()

        await asyncio.gather(
            self.pipe(reader, target_writer),
            self.pipe(target_reader, writer),
            return_exceptions=True,
        )

        target_writer.close()
        with suppress(Exception):
            await target_writer.wait_closed()

    async def pipe(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            while True:
                data = await reader.read(65536)
                if not data:
                    break
                writer.write(data)
                await writer.drain()
        except Exception:
            pass
        finally:
            with suppress(Exception):
                writer.close()

    async def start(self) -> None:
        if self.config["listen_ipv4"]:
            server_v4 = await asyncio.start_server(
                self.handle_client,
                host=self.config["ipv4_host"],
                port=self.config["port"],
                family=socket.AF_INET,
                reuse_address=True,
            )
            self.servers.append(server_v4)
            LOGGER.info("IPv4 listener ready on %s:%s", self.config["ipv4_host"], self.config["port"])

        if self.config["listen_ipv6"]:
            server_v6 = await asyncio.start_server(
                self.handle_client,
                host=self.config["ipv6_host"],
                port=self.config["port"],
                family=socket.AF_INET6,
                reuse_address=True,
            )
            self.servers.append(server_v6)
            LOGGER.info("IPv6 listener ready on [%s]:%s", self.config["ipv6_host"], self.config["port"])

        if not self.servers:
            raise RuntimeError("no listeners were started")

        stop_event = asyncio.Event()

        def request_stop() -> None:
            LOGGER.info("shutdown requested")
            stop_event.set()

        loop = asyncio.get_running_loop()
        for signum in (signal.SIGINT, signal.SIGTERM):
            with suppress(NotImplementedError):
                loop.add_signal_handler(signum, request_stop)

        await stop_event.wait()
        for server in self.servers:
            server.close()
            await server.wait_closed()


def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def main() -> int:
    parser = argparse.ArgumentParser(description="Portable SOCKS5 proxy")
    parser.add_argument("--config", required=True, help="Path to config.json")
    args = parser.parse_args()
    config = load_config(args.config)
    setup_logging(config.get("log_file", ""))
    server = Socks5Server(config)
    try:
        asyncio.run(server.start())
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
  chmod 0755 "$SERVER_PATH"
}

write_config() {
  SOCKS5_JSON_USERNAME=$SOCKS5_USERNAME \
  SOCKS5_JSON_PASSWORD=$SOCKS5_PASSWORD \
  SOCKS5_JSON_PORT=$SOCKS5_PORT \
  SOCKS5_JSON_LISTEN_IPV4=$LISTEN_IPV4 \
  SOCKS5_JSON_LISTEN_IPV6=$LISTEN_IPV6 \
  SOCKS5_JSON_LOG_FILE="${LOG_DIR}/server.log" \
  "$PYTHON_BIN" <<'PY' > "$CONFIG_PATH"
import json
import os

port = int(os.environ["SOCKS5_JSON_PORT"])
listen_ipv4 = os.environ["SOCKS5_JSON_LISTEN_IPV4"].lower() == "true"
listen_ipv6 = os.environ["SOCKS5_JSON_LISTEN_IPV6"].lower() == "true"

config = {
    "port": port,
    "username": os.environ["SOCKS5_JSON_USERNAME"],
    "password": os.environ["SOCKS5_JSON_PASSWORD"],
    "listen_ipv4": listen_ipv4,
    "listen_ipv6": listen_ipv6,
    "ipv4_host": "0.0.0.0",
    "ipv6_host": "::",
    "connect_timeout": 10,
    "log_file": os.environ["SOCKS5_JSON_LOG_FILE"],
}

print(json.dumps(config, ensure_ascii=False, indent=2))
PY
  chmod 0640 "$CONFIG_PATH"
}

write_state() {
  cat > "$STATE_PATH" <<EOF
SERVICE_NAME='${SERVICE_NAME}'
INSTALL_DIR='${INSTALL_DIR}'
ETC_DIR='${ETC_DIR}'
LOG_DIR='${LOG_DIR}'
RUN_USER='${RUN_USER}'
RUN_GROUP='${RUN_GROUP}'
SOCKS5_PORT='${SOCKS5_PORT}'
EOF
  chmod 0640 "$STATE_PATH"
}

write_runner() {
  cat > "$RUNNER_PATH" <<EOF
#!/bin/sh
set -eu
exec ${PYTHON_BIN} ${SERVER_PATH} --config ${CONFIG_PATH}
EOF
  chmod 0755 "$RUNNER_PATH"
}

write_systemd_service() {
  cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=Portable SOCKS5 Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${RUNNER_PATH}
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${LOG_DIR}

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null
}

write_openrc_service() {
  cat > "$OPENRC_SERVICE" <<EOF
#!/sbin/openrc-run

name="Portable SOCKS5 Proxy"
description="Portable SOCKS5 Proxy"
command="${RUNNER_PATH}"
command_user="${RUN_USER}:${RUN_GROUP}"
command_background="yes"
pidfile="/run/${SERVICE_NAME}.pid"
output_log="${LOG_DIR}/openrc.out.log"
error_log="${LOG_DIR}/openrc.err.log"

depend() {
  need net
  use dns logger
}
EOF
  chmod 0755 "$OPENRC_SERVICE"
  rc-update add "$SERVICE_NAME" default >/dev/null 2>&1 || true
}

start_service() {
  case "$INIT_SYSTEM" in
    systemd)
      systemctl restart "$SERVICE_NAME"
      systemctl is-active --quiet "$SERVICE_NAME" || die "service failed to start"
      ;;
    openrc)
      rc-service "$SERVICE_NAME" restart >/dev/null 2>&1 || rc-service "$SERVICE_NAME" start
      rc-service "$SERVICE_NAME" status >/dev/null 2>&1 || die "service failed to start"
      ;;
  esac
}

stop_service() {
  case "$INIT_SYSTEM" in
    systemd) systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true ;;
    openrc) rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true ;;
  esac
}

show_status() {
  case "$INIT_SYSTEM" in
    systemd) systemctl status "$SERVICE_NAME" --no-pager ;;
    openrc) rc-service "$SERVICE_NAME" status ;;
  esac
}

restart_service() {
  case "$INIT_SYSTEM" in
    systemd) systemctl restart "$SERVICE_NAME" ;;
    openrc) rc-service "$SERVICE_NAME" restart ;;
  esac
}

configure_firewall() {
  is_true "$NO_FIREWALL" && return 0

  if command_exists ufw; then
    if ufw status 2>/dev/null | grep -qi "Status: active"; then
      ufw allow "${SOCKS5_PORT}/tcp" >/dev/null
      success "opened port ${SOCKS5_PORT}/tcp in UFW"
    fi
  elif command_exists firewall-cmd; then
    if firewall-cmd --state >/dev/null 2>&1; then
      firewall-cmd --permanent --add-port="${SOCKS5_PORT}/tcp" >/dev/null
      firewall-cmd --reload >/dev/null
      success "opened port ${SOCKS5_PORT}/tcp in firewalld"
    fi
  else
    warn "no managed firewall integration detected; ensure ${SOCKS5_PORT}/tcp is allowed"
  fi
}

test_local_listener() {
  "$PYTHON_BIN" - "$SOCKS5_PORT" "$LISTEN_IPV4" "$LISTEN_IPV6" <<'PY'
import socket
import sys

port = int(sys.argv[1])
listen_ipv4 = sys.argv[2].lower() == "true"
listen_ipv6 = sys.argv[3].lower() == "true"
targets = []
if listen_ipv4:
    targets.append((socket.AF_INET, ("127.0.0.1", port)))
if listen_ipv6:
    targets.append((socket.AF_INET6, ("::1", port, 0, 0)))

for family, address in targets:
    sock = socket.socket(family, socket.SOCK_STREAM)
    sock.settimeout(3)
    sock.connect(address)
    sock.sendall(b"\x05\x01\x00")
    data = sock.recv(2)
    sock.close()
    if len(data) != 2 or data[0] != 0x05:
        raise SystemExit(1)
PY
}

urlencode() {
  "$PYTHON_BIN" - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=""))
PY
}

show_connection_info() {
  user_enc=$(urlencode "$SOCKS5_USERNAME")
  pass_enc=$(urlencode "$SOCKS5_PASSWORD")

  printf '\n'
  success "installation completed"
  printf '%sservice:%s %s\n' "$BLUE" "$NC" "$SERVICE_NAME"
  printf '%sport:%s %s\n' "$BLUE" "$NC" "$SOCKS5_PORT"
  printf '%susername:%s %s\n' "$BLUE" "$NC" "$SOCKS5_USERNAME"
  printf '%spassword:%s %s\n' "$BLUE" "$NC" "$SOCKS5_PASSWORD"
  printf '%sconfig:%s %s\n' "$BLUE" "$NC" "$CONFIG_PATH"
  printf '%slogs:%s %s\n' "$BLUE" "$NC" "${LOG_DIR}/server.log"
  printf '\n'

  if is_public_ipv4 "$DETECTED_IPV4"; then
    printf '%sIPv4:%s socks5://%s:%s@%s:%s\n' "$GREEN" "$NC" "$user_enc" "$pass_enc" "$DETECTED_IPV4" "$SOCKS5_PORT"
  fi
  if is_public_ipv6 "$DETECTED_IPV6"; then
    printf '%sIPv6:%s socks5://%s:%s@[%s]:%s\n' "$GREEN" "$NC" "$user_enc" "$pass_enc" "$DETECTED_IPV6" "$SOCKS5_PORT"
  fi
  if ! is_public_ipv4 "$DETECTED_IPV4" && ! is_public_ipv6 "$DETECTED_IPV6"; then
    warn "public IP auto-detection was unavailable; use your server IP manually"
  fi

  printf '\n'
  printf '%sCommands:%s\n' "$CYAN" "$NC"
  case "$INIT_SYSTEM" in
    systemd)
      printf '  systemctl status %s --no-pager\n' "$SERVICE_NAME"
      printf '  systemctl restart %s\n' "$SERVICE_NAME"
      printf '  journalctl -u %s -f\n' "$SERVICE_NAME"
      ;;
    openrc)
      printf '  rc-service %s status\n' "$SERVICE_NAME"
      printf '  rc-service %s restart\n' "$SERVICE_NAME"
      printf '  tail -f %s\n' "${LOG_DIR}/server.log"
      ;;
  esac
  printf '\n'
}

confirm_uninstall() {
  if is_true "$ASSUME_YES"; then
    return 0
  fi
  printf 'Remove %s and its files? [y/N] ' "$SERVICE_NAME"
  read answer || true
  case "${answer:-n}" in
    y|Y|yes|YES) ;;
    *) die "uninstall cancelled" ;;
  esac
}

load_state_if_present() {
  if [ -f "$STATE_PATH" ]; then
    # shellcheck disable=SC1090
    . "$STATE_PATH"
    refresh_paths
  fi
}

uninstall_service() {
  require_root
  detect_os
  load_state_if_present
  confirm_uninstall
  stop_service
  case "$INIT_SYSTEM" in
    systemd)
      systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
      rm -f "$SYSTEMD_UNIT"
      systemctl daemon-reload
      ;;
    openrc)
      rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
      rm -f "$OPENRC_SERVICE"
      ;;
  esac
  rm -rf "$INSTALL_DIR" "$ETC_DIR" "$LOG_DIR"
  success "uninstall completed"
}

install_service() {
  require_root
  detect_os
  install_packages
  resolve_python
  validate_port
  validate_credentials
  detect_network
  create_runtime_layout
  write_server
  write_config
  write_state
  write_runner
  chown root:root "$SERVER_PATH" "$RUNNER_PATH"
  chown root:"$RUN_GROUP" "$CONFIG_PATH" "$STATE_PATH"

  case "$INIT_SYSTEM" in
    systemd) write_systemd_service ;;
    openrc) write_openrc_service ;;
  esac

  start_service
  configure_firewall
  if test_local_listener; then
    success "local listener test passed"
  else
    warn "local listener test failed; inspect the service logs"
  fi
  show_connection_info
}

main() {
  parse_args "$@"
  case "$COMMAND" in
    install) install_service ;;
    uninstall) uninstall_service ;;
    status)
      require_root
      detect_os
      load_state_if_present
      show_status
      ;;
    restart)
      require_root
      detect_os
      load_state_if_present
      restart_service
      show_status
      ;;
    *) die "unsupported command: $COMMAND" ;;
  esac
}

main "$@"
