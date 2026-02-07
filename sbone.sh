#!/usr/bin/env bash

# 一键部署 sing-box VLESS + Reality 节点（优先 IPv6 出站）
# 支持：自动安装核心、生成配置、启动服务、输出一键导入链接
# 出站：direct 默认优先 IPv6 + 自动回落 IPv4

set -euo pipefail

echo "正在安装 sing-box 核心..."
bash <(curl -fsSL https://sing-box.app/install.sh)

echo "生成配置..."
mkdir -p /etc/sing-box

read -p "监听端口 [443]: " PORT
PORT=${PORT:-443}
read -p "伪装域名 [www.microsoft.com]: " SNI
SNI=${SNI:-www.microsoft.com}

UUID=$(sing-box generate uuid)

# 一次性生成密钥对，确保私钥和公钥匹配
KEYPAIR=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYPAIR" | grep PrivateKey | awk -F'"' '{print $4}')
PUBLIC_KEY=$(echo "$KEYPAIR" | grep PublicKey | awk -F'"' '{print $4}')

SHORT_ID=$(sing-box generate rand --hex 8)

cat > /etc/sing-box/config.json <<EOS
{
  "log": {"level": "info"},
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": $PORT,
      "sniff": true,
      "sniff_override_destination": true,
      "users": [{"uuid": "$UUID", "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "reality": {
          "enabled": true,
          "handshake": {"server": "$SNI", "server_port": 443},
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ]
}
EOS

echo "创建并启动服务..."
cat > /etc/systemd/system/sing-box.service <<EOS
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOS

systemctl daemon-reload
systemctl enable --now sing-box

IPV6=$(ip -6 addr show | grep global | awk '{print $2}' | cut -d'/' -f1 | head -1)
if [[ -z "$IPV6" ]]; then
    echo "警告：未检测到全局 IPv6 地址。请手动检查网络配置，或在链接中使用您的 IPv6 地址替换占位符。"
    IPV6_ADDR="您的IPv6地址（带方括号，如[xxxx::xxxx]）"
else
    IPV6_ADDR="[$IPV6]"
fi

VLESS_LINK="vless://${UUID}@${IPV6_ADDR}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&packetEncoding=2&type=tcp&headerType=none#SingBox-IPv6-Node"

echo
echo "部署完成！服务已启动。"
echo "一键导入链接（直接复制到客户端）："
echo "$VLESS_LINK"
echo
echo "客户端参数备查："
echo "地址: ${IPV6_ADDR}"
echo "端口: $PORT"
echo "UUID: $UUID"
echo "Public Key: $PUBLIC_KEY"
echo "Short ID: $SHORT_ID"
echo "SNI: $SNI"
echo
echo "验证服务：systemctl status sing-box"
