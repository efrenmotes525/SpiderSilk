# SpiderSilk / TopFlow 服务端一键部署

当前仓库包含：

- `headbridge-server`：服务端二进制
- `topflow-server.sh`：统一安装 / 更新 / 卸载脚本

特性：

- 默认下载 **本仓库** 的 `headbridge-server`
- 安装完成后输出 **导入链接 + 终端二维码**
- 支持 IPv4 / IPv6 公网地址
- 支持 `install / update / uninstall`
- 监听 `80 / 443` 等低端口时自动处理绑定权限

## 一键安装

> Linux 上直接执行；如果你已经是 root，不要再套 `sudo`

### 推荐：8443

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen 0.0.0.0:8443 --public-endpoint 你的公网IP或域名:8443
```

### 443

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen 0.0.0.0:443 --public-endpoint 你的公网IP或域名:443
```

### IPv6

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh install --listen [::]:443 --public-endpoint [你的IPv6]:443
```

## 更新

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh update
```

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/efrenmotes525/SpiderSilk/main/topflow-server.sh | sed 's/\r$//' > /tmp/topflow-server.sh && chmod +x /tmp/topflow-server.sh && /tmp/topflow-server.sh uninstall --yes
```

## 常用命令

```bash
systemctl status topflow-server --no-pager
journalctl -u topflow-server -f
systemctl restart topflow-server
```

## 脚本参数

```bash
/tmp/topflow-server.sh install \
  --listen 0.0.0.0:8443 \
  --public-endpoint your.domain.com:8443 \
  --psk "你的Base64-PSK" \
  --node-name "TopFlow" \
  --group-name "AutoDeploy"
```

支持的关键参数：

- `--listen <host:port>`
- `--public-endpoint <host:port>`
- `--psk <Base64>`
- `--download-url <url>`
- `--node-name <name>`
- `--group-name <name>`
- `--service-name <name>`
- `--install-dir <dir>`
- `--etc-dir <dir>`

## 注意

- 安装完成后，脚本会打印：
  - 客户端地址
  - 导入链接
  - 终端二维码
- 若自动探测公网地址失败，请手动加 `--public-endpoint`
- 若是 IPv6，请使用 `[IPv6]:端口` 格式
