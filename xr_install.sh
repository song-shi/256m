#!/bin/bash
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}
yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

if type apt >/dev/null 2>&1; then
	export DEBIAN_FRONTEND=noninteractive
	apt update -qq
	apt install -y -qq curl unzip 
fi


if [[ -f "/root/Xray/xray" ]]; then
    green "xray文件已存在！"
else
    echo "开始下载xray文件..."
    wget https://github.com/XTLS/Xray-core/releases/download/v1.8.1/Xray-linux-64.zip
    cd /root
    mkdir ./Xray
    unzip -d /root/Xray Xray-linux-64.zip
    rm Xray-linux-64.zip
    cd /root/Xray
    if [[ -f "xray" ]]; then
        green "下载成功！"
    else
        red "下载失败！"
        exit 1
    fi
fi

read -p "请输入reality端口号：" port
sign=false
until $sign; do
    if [[ -z $port ]]; then
        red "错误：端口号不能为空，请输入小鸡管家给定的可用端口号!"
        read -p "请重新输入reality端口号：" port
        continue
    fi
    if ! echo "$port" | grep -qE '^[0-9]+$';then
        red "错误：端口号必须是数字!"
        read -p "请重新输入reality端口号：" port
        continue
    fi
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        red "错误：端口号必须介于1~65525之间!"
        read -p "请重新输入reality端口号：" port
        continue
    fi
    if [[ -z $(nc -zv 127.0.0.1 $port 2>&1 | grep "open") ]]; then
        green "成功：端口号 $port 可用!"
        sign=true
    else
        red "错误：$port 已被占用！"
        read -p "请重新输入reality端口号：" port
    fi
done

UUID=$(cat /proc/sys/kernel/random/uuid)
read -rp "请输入回落域名[默认: code.tecmeet.com]: " dest_server
[[ -z $dest_server ]] && dest_server="code.tecmeet.com"
short_id=$(dd bs=4 count=2 if=/dev/urandom | xxd -p -c 8)
keys=$(/root/Xray/xray x25519)
private_key=$(echo $keys | awk -F " " '{print $3}')
public_key=$(echo $keys | awk -F " " '{print $6}')
green "private_key: $private_key"
green "public_key: $public_key"
green "short_id: $short_id"

rm -f /root/Xray/config.json
cat << EOF > /root/Xray/config.json
{
  "inbounds": [
      {
          "listen": "0.0.0.0",
          "port": $port,
          "protocol": "vless",
          "settings": {
              "clients": [
                  {
                      "id": "$UUID",
                      "flow": "xtls-rprx-vision"
                  }
              ],
              "decryption": "none"
          },
          "streamSettings": {
              "network": "tcp",
              "security": "reality",
              "realitySettings": {
                  "show": true,
                  "dest": "$dest_server:443",
                  "xver": 0,
                  "serverNames": [
                      "$dest_server"
                  ],
                  "privateKey": "$private_key",
                  "minClientVer": "",
                  "maxClientVer": "",
                  "maxTimeDiff": 0,
                  "shortIds": [
                  "$short_id"
                  ]
              }
          }
      }
  ],
  "outbounds": [
      {
          "protocol": "freedom",
          "tag": "direct"
      },
      {
          "protocol": "blackhole",
          "tag": "blocked"
      }
  ],
  "policy": {
    "handshake": 4,
    "connIdle": 300,
    "uplinkOnly": 2,
    "downlinkOnly": 5,
    "statsUserUplink": false,
    "statsUserDownlink": false,
    "bufferSize": 1024
  }
}
EOF

IP=$(wget -qO- --no-check-certificate -U Mozilla https://api.ip.sb/geoip | sed -n 's/.*"ip": *"\([^"]*\).*/\1/p')
green "您的IP为：$IP"

share_link="vless://$UUID@$IP:$port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$dest_server&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#32M-Reality"
echo ${share_link} > /root/Xray/share-link.txt

cat << EOF > /root/Xray/clash-meta.yaml
port: 7890
socks-port: 7891
allow-lan: true
mode: Rule
log-level: info
external-controller: :9090
dns:
    enable: true
    ipv6: false
    default-nameserver: [223.5.5.5, 119.29.29.29]
    enhanced-mode: fake-ip
    fake-ip-range: 198.18.0.1/16
    use-hosts: true
    nameserver: ['https://doh.pub/dns-query', 'https://dns.alidns.com/dns-query']
    fallback: ['https://doh.dns.sb/dns-query', 'https://dns.cloudflare.com/dns-query', 'https://dns.twnic.tw/dns-query', 'tls://8.8.4.4:853']
    fallback-filter: { geoip: true, ipcidr: [240.0.0.0/4, 0.0.0.0/32] }

proxies:
  - name: 32M-Reality
    type: vless
    server: $IP
    port: $port
    uuid: $UUID
    network: tcp
    tls: true
    udp: true
    xudp: true
    flow: xtls-rprx-vision
    servername: $dest_server
    reality-opts:
      public-key: "$public_key"
      short-id: "$short_id"
    client-fingerprint: chrome

proxy-groups:
  - name: 🚀 节点选择
    type: select
    proxies:
      - 32M-Reality
      - DIRECT

rules:
  - GEOIP,CN,DIRECT,no-resolve
  - MATCH,🚀 节点选择
EOF

yellow "Clash Meta配置文件已保存到：/root/Xray/clash-meta.yaml"
yellow "reality的分享链接已保存到：/root/Xray/share-link.txt"
echo
green "reality的分享链接为："
red $share_link

cat << EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
LogsDirectory=xray
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/root/Xray/xray run -config /root/Xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl enable xray --now
systemctl daemon-reload
systemctl restart xray
systemctl status xray

cd /root
