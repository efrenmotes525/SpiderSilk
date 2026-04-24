# SpiderSilk / TopFlow Server

一键部署 TopFlow/HeadBridge 服务端。仓库地址：<https://github.com/efrenmotes525/SpiderSilk>

本仓库面向 VPS 部署场景，提供 Linux x86_64 服务端二进制与 systemd 安装脚本。安装完成后会自动生成客户端配置清单、`topflow://` 导入链接和终端二维码。

## 仓库内容

| 文件 | 说明 |
| --- | --- |
| `headbridge-server` | HeadBridge 服务端二进制，当前为 Linux x86_64 ELF。 |
| `topflow-server.sh` | 推荐使用的一键安装 / 更新 / 卸载脚本；会生成 TopFlow 导入链接和二维码。 |
| `headbridge-server.sh` | HeadBridge 原生管理脚本；适合高级参数和 VVIP 回程中继场景。 |

## 功能特性

- 一条命令安装并注册 `systemd` 服务。
- 默认从本仓库下载 `headbridge-server`。
- 自动生成 32 字节 Base64 PSK；也支持手动指定。
- 自动输出客户端字段、`topflow://` 导入链接和终端二维码。
- 支持 IPv4 / IPv6 公网地址。
- 支持 `install` / `update` / `uninstall`。
- 监听 `80` / `443` 等低端口时自动授予 `cap_net_bind_service`。
- 支持 UFW / firewalld 自动放行主端口。
- 更新失败会自动回滚到旧二进制。

## 系统要求

- Linux x86_64 VPS。
- `systemd` 主机环境。
- 需要 root 权限或 sudo。
- 脚本会自动安装运行依赖：`curl`、`openssl`、`qrencode`、`python3`、`setcap` 等。

> ARM / AArch64 机器需要自行提供对应架构的 `headbridge-server`，并通过 `--download-url` 指定下载地址。

## 快速安装

> 如果已经是 root，不要再套 `sudo`。
>
> 请把命令中的 `your.domain.com` 或 IP 换成你的 VPS 公网地址。

### 一键开启魅影：8443 主端口 + 8444 回程端口

> 这是你要的“直接复制即可开启魅影”的版本：只需要把 `your.domain.com` 改成你的 VPS 公网 IP 或域名。
>
> 客户端导入链接仍然使用主端口 `8443`；魅影回程端口是 `8444`，需要在云厂商安全组里同时放行 `8443/tcp` 和 `8444/tcp`。

```bash
curl -fsSL "https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh?$(date +%s)" | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen 0.0.0.0:8443 --vvip-relay-listen 0.0.0.0:8444 --public-endpoint your.domain.com:8443 --node-name "TopFlow-8443" --group-name "AutoDeploy"
```

### 一键开启魅影：443 主端口 + 444 回程端口

> 如果你想伪装成常见 HTTPS 端口，用这个。需要在云厂商安全组里同时放行 `443/tcp` 和 `444/tcp`。

```bash
curl -fsSL "https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh?$(date +%s)" | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen 0.0.0.0:443 --vvip-relay-listen 0.0.0.0:444 --public-endpoint your.domain.com:443 --node-name "TopFlow-443" --group-name "AutoDeploy"
```

### 一键开启魅影：27017 主端口 + 27018 回程端口

> 如果你想用非常规端口，可以用这一组。需要在云厂商安全组里同时放行 `27017/tcp` 和 `27018/tcp`。

```bash
curl -fsSL "https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh?$(date +%s)" | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen 0.0.0.0:27017 --vvip-relay-listen 0.0.0.0:27018 --public-endpoint your.domain.com:27017 --node-name "TopFlow-27017" --group-name "AutoDeploy"
```
### 推荐：8443

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen 0.0.0.0:8443 --public-endpoint your.domain.com:8443
```

### 使用 443

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen 0.0.0.0:443 --public-endpoint your.domain.com:443
```

### IPv6

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen [::]:443 --public-endpoint [2001:db8::1]:443
```

### 指定固定 PSK

```bash
PSK="$(openssl rand -base64 32 | tr -d '\r\n')"
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh
chmod +x /tmp/topflow-server.sh
/tmp/topflow-server.sh install \
  --listen 0.0.0.0:8443 \
  --public-endpoint your.domain.com:8443 \
  --psk "$PSK" \
  --node-name "TopFlow" \
  --group-name "AutoDeploy"
```

## 安装完成后

脚本会打印类似下面的信息：

```text
客户端配置清单:
  host        = your.domain.com
  port        = 8443
  sni         = www.cloudflare.com
  insecureTls = true
  pskB64      = <自动生成或手动指定的 PSK>
  kernelType  = HeadBridge

可复制导入链接:
topflow://import?zip=deflate&data=...

终端二维码:
...
```

在 TopFlow 客户端中可以直接扫码或复制 `topflow://` 链接导入节点。

## 常用命令

```bash
systemctl status topflow-server --no-pager
journalctl -u topflow-server -f
systemctl restart topflow-server
```

查看监听端口：

```bash
ss -ltnp | grep -E ':(443|8443)\b'
```

查看安装文件：

```bash
ls -l /opt/topflow-server
cat /etc/topflow-server/topflow-server.env
```

## 更新

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh update
```

如果更新失败，脚本会自动恢复旧二进制并打印最近日志。

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh uninstall --yes
```

保留配置：

```bash
/tmp/topflow-server.sh uninstall --yes --keep-config
```

保留运行用户：

```bash
/tmp/topflow-server.sh uninstall --yes --keep-user
```

## 参数说明

### `topflow-server.sh install`

| 参数 | 说明 |
| --- | --- |
| `--listen <host:port>` | 服务监听地址，默认 `0.0.0.0:8888`。IPv6 建议写成 `[::]:443`。 |
| `--public-endpoint <host:port>` | 写入客户端配置的公网地址。监听 `0.0.0.0` / `[::]` 时建议显式指定。 |
| `--psk <Base64>` | 32 字节 PSK 的 Base64 字符串；不传则自动生成。 |
| `--node-name <name>` | 导入到客户端后的节点名称，默认 `TopFlow`。 |
| `--group-name <name>` | 导入到客户端后的分组名称，默认 `AutoDeploy`。 |
| `--sni <host>` | 客户端配置中的 SNI，默认 `www.cloudflare.com`。 |
| `--vvip-relay-listen <host:port\|auto\|off>` | Enable VVIP/phantom return relay; use main port +1, e.g. `443 -> 444`. |
| `--max-connections <num>` | 最大连接数，默认 `10000`。 |
| `--download-url <url>` | 自定义服务端二进制下载地址。 |
| `--ca-cert <path>` / `--ca-key <path>` | 指定 CA 证书和私钥路径。 |
| `--generate-ca` | 启动时生成 CA。 |
| `--debug` / `-d` | 开启调试日志。 |
| `--skip-cert-verify` | 导出 `insecureTls=true`，并透传给服务端。 |
| `--no-firewall` | 不自动放行防火墙端口。 |
| `--user <name>` / `--group <name>` | 服务运行用户和用户组。 |
| `--service-name <name>` | systemd 服务名，默认 `topflow-server`。 |
| `--install-dir <dir>` | 安装目录，默认 `/opt/topflow-server`。 |
| `--etc-dir <dir>` | 配置目录，默认 `/etc/topflow-server`。 |

### 环境变量

常用环境变量会写入配置文件，适合脚本化安装：

```bash
TOPFLOW_NODE_NAME="My VPS" \
TOPFLOW_GROUP_NAME="Production" \
TOPFLOW_SNI="www.cloudflare.com" \
/tmp/topflow-server.sh install --listen 0.0.0.0:8443 --public-endpoint your.domain.com:8443
```

## VVIP / Phantom return relay

`topflow-server.sh` now supports `--vvip-relay-listen` directly. The installer prints the client config, `topflow://` import link, terminal QR code, PSK, and relay listener.

### One-line install: 443 + 444

```bash
curl -fsSL "https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh?$(date +%s)" | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen 0.0.0.0:443 --vvip-relay-listen 0.0.0.0:444 --public-endpoint your.domain.com:443 --node-name "TopFlow-443" --group-name "AutoDeploy"
```

### One-line install: 8443 + 8444

```bash
curl -fsSL "https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh?$(date +%s)" | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen 0.0.0.0:8443 --vvip-relay-listen 0.0.0.0:8444 --public-endpoint your.domain.com:8443 --node-name "TopFlow-8443" --group-name "AutoDeploy"
```

Check listening ports:

```bash
ss -ltnp | grep -E ':(443|444|8443|8444|27017|27018)\b'
```

Common mapping:

| Main port | VVIP/phantom relay port |
| --- | --- |
| `443` | `444` |
| `8443` | `8444` |
| `27017` | `27018` |

Cloud security group must allow both the main port and the relay port.

## 故障排查

### 1. 客户端无法连接

```bash
systemctl status topflow-server --no-pager
journalctl -u topflow-server -n 100 --no-pager
ss -ltnp | grep -E ':(443|8443|8444)\b'
```

重点检查：

- `--public-endpoint` 是否是真实公网 IP / 域名。
- VPS 安全组是否放行主端口。
- 系统防火墙是否放行主端口。
- 客户端 `pskB64` 是否和服务端一致。

### 2. 443 / 80 启动失败

脚本会自动设置 `cap_net_bind_service`，如果仍失败，检查：

```bash
getcap /opt/topflow-server/headbridge-server
journalctl -u topflow-server -n 100 --no-pager
```

也可以改用非特权端口，例如 `8443`。

### 3. VVIP 图片 / 视频仍无法加载

检查主端口和回程端口是否都能访问：

```bash
ss -ltnp | grep -E ':(8443|8444|443|444|27017|27018)\b'
journalctl -u topflow-server -n 100 --no-pager
```

同时确认：

- 云厂商安全组放行主端口和回程端口。
- 系统防火墙放行主端口和回程端口。
- 多台 VPS 的回程端口规则保持一致，建议使用“主端口 + 1”。

## 安全建议

- 妥善保存安装时输出的 `PSK`，客户端必须使用同一个 `pskB64`。
- 不要把包含真实 PSK 的日志、截图或导入链接公开发布。
- 推荐优先使用 `8443`，确认稳定后再切换到 `443`。
- 多节点部署时，建议每个节点使用不同 PSK。
