# SpiderSilk / TopFlow Server

欢迎各位大佬加入官方TG群：https://t.me/+ghA_kXJ4h41jYWRk

欢迎各位大佬加入官方TG群：https://t.me/+ghA_kXJ4h41jYWRk

欢迎各位大佬加入官方TG群：https://t.me/+ghA_kXJ4h41jYWRk

一键部署 TopFlow/HeadBridge 服务端。仓库地址：<https://github.com/efrenmotes525/SpiderSilk>

本仓库面向 VPS 部署场景，提供 Linux x86_64 服务端二进制与 systemd 安装脚本。安装完成后会自动生成客户端配置清单、`topflow://` 导入链接和终端二维码。

## 仓库内容

| 文件 | 说明 |
| --- | --- |
| `headbridge-server` | HeadBridge 服务端二进制，当前为 Linux x86_64 ELF。 |
| `topflow-server.sh` | 推荐使用的一键安装 / 更新 / 卸载脚本；会生成 TopFlow 导入链接和二维码。 |
| `headbridge-server.sh` | HeadBridge 原生管理脚本；适合高级参数和 VVIP 回程中继场景。 |
| `release/headbridge-server-alpine-openrc.sh` | Alpine Linux / OpenRC 专用安装脚本，默认下载 `headbridge-server-alpine-x86_64`。 |

## 功能特性

- 一条命令安装并注册 `systemd` 服务。
- 默认从本仓库下载 `headbridge-server`。
- 默认部署端口统一为 `6379`。
- 自动生成 32 字节 Base64 PSK；也支持手动指定。
- 自动生成管理 Token；安装导入链接会带上 `adminToken`，用于监控大屏、`β 转发`、端口转发和隧道转发。
- 自动输出客户端字段、`topflow://` 导入链接和终端二维码。
- 默认自动检测 IPv4 / IPv6 / 双栈；双栈 VPS 会自动导出 IPv4 与 IPv6 两个客户端节点。
- 支持 `install` / `update` / `uninstall`。
- 支持 VVIP / 魅影回程中继，默认推荐 `6379 + 6380`。
- 支持 UFW / firewalld 自动放行主端口与回程端口。
- 更新失败会自动回滚到旧二进制。
- 客户端已支持 `β 转发`、端口转发、隧道转发、节点监控大屏、多节点指标查看等功能。

## 系统要求

- Linux x86_64 VPS。
- `systemd` 主机环境。
- 需要 root 权限或 sudo。
- 脚本会自动安装运行依赖：`curl`、`openssl`、`qrencode`、`python3`、`setcap` 等。

> ARM / AArch64 机器需要自行提供对应架构的 `headbridge-server`，并通过 `--download-url` 指定下载地址。

## 快速安装

> 如果已经是 root，不要再套 `sudo`。
>
> 不传 `--listen` / `--public-endpoint` 时，脚本会自动检测公网 IPv4/IPv6。双栈主机会监听 `[::]:6379` 并在导入链接里同时写入 IPv4 与 IPv6 节点。

### 自动检测双栈：默认 6379

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install
```

### 自动检测双栈：显式指定 6379

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen auto:6379
```

### 自动检测双栈 + 默认开启 VVIP 魅影：6379 + 6380 回程

> 自动检测 IPv4/IPv6/双栈；双栈主机会监听 `[::]:6379`，导入链接里同时生成 IPv4 与 IPv6 节点，并默认开启 VVIP 魅影。需要在系统防火墙/云安全组放行 `6379/tcp` 和 `6380/tcp`。

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --vvip-relay-listen auto
```

### 一键开启魅影：6379 主端口 + 6380 回程端口

> 这是推荐的标准部署方式：只需要把 `your.domain.com` 改成你的 VPS 公网 IP 或域名。
>
> 客户端导入链接仍然使用主端口 `6379`；魅影回程端口是 `6380`，需要在云厂商安全组里同时放行 `6379/tcp` 和 `6380/tcp`。

```bash
curl -fsSL "https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh?$(date +%s)" | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen 0.0.0.0:6379 --vvip-relay-listen 0.0.0.0:6380 --public-endpoint your.domain.com:6379 --node-name "TopFlow-6379" --group-name "AutoDeploy"
```

### 手动指定 IPv6：6379

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen [::]:6379 --public-endpoint [2001:db8::1]:6379
```

### 指定固定 PSK 和管理 Token

```bash
PSK="$(openssl rand -base64 32 | tr -d '\r\n')"
ADMIN_TOKEN="$(openssl rand -base64 32 | tr -d '\r\n')"
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh
chmod +x /tmp/topflow-server.sh
/tmp/topflow-server.sh install \
  --listen 0.0.0.0:6379 \
  --public-endpoint your.domain.com:6379 \
  --psk "$PSK" \
  --admin-token "$ADMIN_TOKEN" \
  --node-name "TopFlow" \
  --group-name "AutoDeploy"
```

## 安装完成后

脚本会打印类似下面的信息：

```text
客户端配置清单:
  host        = your.domain.com
  port        = 6379
  sni         = www.cloudflare.com
  insecureTls = true
  vvipEnabled = false
  vvipRelay   = off
  pskB64      = <自动生成或手动指定的 PSK>
  adminToken  = <自动生成或手动指定的管理 Token>
  kernelType  = HeadBridge

可复制导入链接:
topflow://import?zip=deflate&data=...

终端二维码:
...
```

在 TopFlow 客户端中可以直接扫码或复制 `topflow://` 链接导入节点。导入链接会同时包含 `pskB64` 和 `adminToken`：`pskB64` 用于基础连接，`adminToken` 用于监控大屏、端口转发、隧道转发等管理功能。

## 常用命令

```bash
systemctl status topflow-server --no-pager
journalctl -u topflow-server -f
systemctl restart topflow-server
```

查看监听端口：

```bash
ss -ltnp | grep -E ':(6379|6380)\b'
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
| `--listen <host:port\|auto[:port]>` | 服务监听地址，默认 `auto:6379`。脚本自动检测网络栈：双栈/IPv6-only 用 `[::]:port`，IPv4-only 用 `0.0.0.0:port`。 |
| `--public-endpoint <host:port[,host:port]>` | 写入客户端配置的公网地址。不传时自动探测；双栈会生成 IPv4 与 IPv6 两个节点。 |
| `--psk <Base64>` | 32 字节 PSK 的 Base64 字符串；不传则自动生成。 |
| `--admin-token <token>` | 管理 Token；不传或传空值时自动生成。客户端监控大屏、`β 转发`、端口转发、隧道转发都需要它鉴权。 |
| `--node-name <name>` | 导入到客户端后的节点名称，默认 `TopFlow`。 |
| `--group-name <name>` | 导入到客户端后的分组名称，默认 `AutoDeploy`。 |
| `--sni <host>` | 客户端配置中的 SNI，默认 `www.cloudflare.com`。 |
| `--vvip-relay-listen <host:port\|auto\|off>` | 开启 VVIP / 魅影回程监听。推荐默认 `6379 -> 6380`，也就是主端口 + 1。 |
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
TOPFLOW_ADMIN_TOKEN="$(openssl rand -base64 32 | tr -d '\r\n')" \
/tmp/topflow-server.sh install --listen 0.0.0.0:6379 --public-endpoint your.domain.com:6379
```

## VVIP / Phantom return relay

`topflow-server.sh` 已支持 `--vvip-relay-listen` 直接开启魅影回程。安装器会同时打印客户端配置、`topflow://` 导入链接、终端二维码、PSK、管理 Token 和回程监听端口。

### One-line install: 6379 + 6380

```bash
curl -fsSL "https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh?$(date +%s)" | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen 0.0.0.0:6379 --vvip-relay-listen 0.0.0.0:6380 --public-endpoint your.domain.com:6379 --node-name "TopFlow-6379" --group-name "AutoDeploy"
```

Check listening ports:

```bash
ss -ltnp | grep -E ':(6379|6380)\b'
```

Common mapping:

| Main port | VVIP/phantom relay port |
| --- | --- |
| `6379` | `6380` |

Cloud security group must allow both the main port and the relay port.

## Alpine / OpenRC 安装

如果你的 VPS 是 Alpine Linux，不要使用 systemd 脚本，改用 `release/headbridge-server-alpine-openrc.sh`。这个脚本会使用 OpenRC 注册服务，并默认下载 Alpine 专用服务端：

```text
https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/headbridge-server-alpine-x86_64
```

> 你提供的 GitHub `blob` 页面地址也可以传给 `--download-url`，脚本会自动转换成 raw 下载地址，避免下载到 HTML 页面。

### Alpine 一键安装：默认 6379

```sh
curl -fsSL https://github.com/efrenmotes525/SpiderSilk/blob/main/headbridge-server-alpine-openrc.sh -o /tmp/headbridge-server-alpine-openrc.sh
chmod +x /tmp/headbridge-server-alpine-openrc.sh
sh /tmp/headbridge-server-alpine-openrc.sh install
```

默认行为：

- 主端口监听 `0.0.0.0:6379`
- 自动生成 32 字节 Base64 `PSK`
- 自动生成 `admin token`
- 自动安装 Alpine 依赖
- 自动注册并启动 OpenRC 服务

脚本会安装这些 Alpine 依赖：

- `ca-certificates`：让 `curl` 可以正常访问 HTTPS 下载地址
- `curl`：下载 Alpine 服务端二进制
- `openssl`：生成和校验 PSK / 管理 Token
- `openrc`：提供 `rc-service`、`rc-update`、`checkpath`、`start-stop-daemon`
- `libcap`：需要低端口时提供 `setcap`

### Alpine 开启魅影：6379 + 6380

```sh
sh /tmp/headbridge-server-alpine-openrc.sh install --vvip-relay-listen auto
```

需要在云厂商安全组和 Alpine 本机防火墙中放行：

- `6379/tcp`：主连接端口
- `6380/tcp`：魅影 / VVIP 回程端口

### Alpine 手动指定管理 Token

```sh
ADMIN_TOKEN="$(openssl rand -base64 32 | tr -d '\r\n')"
sh /tmp/headbridge-server-alpine-openrc.sh install \
  --listen 0.0.0.0:6379 \
  --admin-token "$ADMIN_TOKEN"
```

如果不传 `--admin-token`，脚本会自动生成。安装完成后会打印 `psk` 和 `admin token`，并保存到：

```sh
/etc/headbridge-server/headbridge-server.env
```

手动添加 Alpine 节点到 Windows 客户端时，除了 `host`、`port=6379`、`pskB64`，还要把 `admin token` 填到客户端的 `管理 Token` 字段，否则监控大屏、端口转发、隧道转发无法鉴权。

### Alpine 常用命令

```sh
rc-service headbridge-server status
rc-service headbridge-server restart
tail -f /var/log/messages
cat /etc/headbridge-server/headbridge-server.env
```

如果是旧 Alpine 节点升级到新版脚本，执行 `update` 时脚本也会检查旧配置里是否缺少 `admin token`；如果缺少，会自动生成并写回 env，然后重启服务。

## 客户端新增功能使用说明

下面这部分是给已经成功部署服务端、并已经把节点导入到 Windows 客户端之后使用的。客户端当前已经支持 `β 转发`、端口转发、隧道转发、监控大屏等功能。

### 节点导入与基础连接

推荐流程：

1. 在服务端安装完成后，复制输出的 `topflow://import?...`
2. 打开 Windows 客户端
3. 点击顶部 `⭳ 粘贴`
4. 导入后点击 `◔ 全测`
5. 选择延迟正常的节点并连接

如果你是复制脚本自动生成的导入链接，客户端会自动带上 `管理 Token`。如果你是手动添加节点，除了 `host`、`port`、`pskB64` 之外，也要把安装输出里的 `管理 Token` 填到客户端节点编辑页的 `管理 Token` 字段，否则基础连接可能正常，但监控大屏、端口转发和隧道转发会因为没有管理鉴权而不可用。

主界面上最常用的按钮通常包括：

- `⭳ 粘贴`：从剪贴板导入 `topflow://` 链接 / JSON / 二维码内容
- `◔ 全测`：测试全部节点延迟
- `☷ 魅影`：给已选 HeadBridge 节点开启 VVIP / 魅影
- `β 转发`：打开转发策略控制中心
- `监控大屏`：打开多节点监控大屏

### `β 转发` 总览

客户端顶部的 `β 转发` 会打开“顶流转发策略控制中心”。这里主要有两类用法：

- 端口转发
- 隧道转发

推荐使用顺序：

1. 先确保当前节点已经能正常连接
2. 再打开 `β 转发`
3. 新建一条策略
4. 先做最简单的一条规则，确认跑通后再增加限速、配额、计费等配置

### 端口转发怎么用

当你希望“命中某个监听端口的流量，被送去指定目标 IP / 域名 + 目标端口”时，使用端口转发。

在转发策略里重点填写：

- `监听端口`
- `目标 IP / 域名`
- `目标端口`

示例：

- 监听端口：`31080`
- 目标 IP / 域名：`example.com`
- 目标端口：`443`

含义：

- 命中这条规则的流量，会被转发到 `example.com:443`

建议：

- 第一次使用时，限速、流量配额、转发数量上限都可以先留空
- 每次修改后都点一次 `保存转发策略`
- 保存后马上做一次实际连接验证

如果不生效，优先检查：

- 当前节点是否在线
- 当前节点是否已经填写 `管理 Token`
- `监听端口` 是否填错
- `目标 IP / 域名` 是否填错
- `目标端口` 是否填错

### 隧道转发怎么用

当你不是想把流量送给普通网站或服务器，而是想送给另一个在线隧道时，使用隧道转发。

在策略里重点填写：

- `目标用户名`
- `目标密码`
- `目标隧道`

可以把它理解成：

- 当前链路接到流量后，不直接去访问网站，而是再交给另一个在线隧道处理

适合场景：

- 多隧道联动
- 转发给另一条已经在线的 HeadBridge 隧道
- 做更复杂的转发链路组合

如果你只是普通用户，建议先掌握端口转发，再尝试隧道转发。

### 节点监控大屏怎么用

客户端顶部的 `监控大屏` 会打开“节点监控大屏”，支持同页展示多个 HeadBridge 节点的 CPU / 内存 / 磁盘 / 网络指标。

适合场景：

- 多 VPS 日常巡检
- 节点稳定性排查
- 演示多节点运行情况
- 长期开着做值守监控

打开后通常会看到：

- 节点总数
- 在线节点数
- 平均 CPU
- 平均内存
- 网络概览
- 异常数量

常用按钮包括：

- `重建已勾选`
- `补上已勾选`
- `全部可监控`
- `清空画布`
- `保存截图`
- `立即刷新`

使用建议：

- 左边选择你要观察的节点
- 右边画布查看各节点状态
- 数据感觉没更新时，先点 `立即刷新`
- 需要发给同事或用户时，用 `保存截图`

如果监控大屏没有数据，优先检查：

- 节点是否已经在线
- 节点配置里是否有 `管理 Token`
- 服务端是否已更新到较新版本
- 当前是否使用的是 HeadBridge 节点
- 客户端日志和服务端日志是否报错

## 故障排查

### 1. 客户端无法连接

```bash
systemctl status topflow-server --no-pager
journalctl -u topflow-server -n 100 --no-pager
ss -ltnp | grep -E ':(6379|6380)\b'
```

重点检查：

- `--public-endpoint` 是否是真实公网 IP / 域名。
- VPS 安全组是否放行主端口。
- 系统防火墙是否放行主端口。
- 客户端 `pskB64` 是否和服务端一致。
- 手动添加节点时，客户端 `管理 Token` 是否和 `/etc/topflow-server/topflow-server.env` 里的 `TOPFLOW_ADMIN_TOKEN` 一致。

### 2. 服务端启动失败

优先检查：

```bash
journalctl -u topflow-server -n 100 --no-pager
cat /etc/topflow-server/topflow-server.env
```

如果你自行改成别的低端口，再额外检查：

```bash
getcap /opt/topflow-server/headbridge-server
```

### 3. VVIP 图片 / 视频仍无法加载

检查主端口和回程端口是否都能访问：

```bash
ss -ltnp | grep -E ':(6379|6380)\b'
journalctl -u topflow-server -n 100 --no-pager
```

同时确认：

- 云厂商安全组放行主端口和回程端口。
- 系统防火墙放行主端口和回程端口。
- 多台 VPS 的回程端口规则保持一致，建议使用“主端口 + 1”。

### 4. 端口转发或隧道转发不生效

优先检查：

- 当前节点是否已经连接成功
- 当前节点是否已经导入或填写 `管理 Token`
- 转发策略是否已经点击 `保存转发策略`
- 端口转发里的 `监听端口` / `目标 IP / 域名` / `目标端口` 是否正确
- 隧道转发里的 `目标用户名` / `目标密码` / `目标隧道` 是否正确
- 客户端底部日志是否有明显报错

### 5. 监控大屏没有数据

优先检查：

- 当前监控的节点是否在线
- 当前节点是否已经导入或填写 `管理 Token`
- 是否点击过 `立即刷新`
- 服务端是否较新
- 客户端和服务端日志是否有持续报错

## 安全建议

- 妥善保存安装时输出的 `PSK` 和 `管理 Token`。客户端必须使用同一个 `pskB64`，管理功能必须使用同一个 `adminToken`。
- 不要把包含真实 PSK、管理 Token 或导入链接的日志、截图公开发布。
- 推荐统一使用 `6379`，魅影回程统一使用 `6380`，这样最方便部署、排障和批量维护。
- 多节点部署时，建议每个节点使用不同 PSK。
