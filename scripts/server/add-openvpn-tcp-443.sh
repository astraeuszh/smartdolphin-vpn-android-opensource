#!/bin/bash
# 在现有 OpenVPN 服务器上添加 TCP 443 监听（与网站/内核统一；不碰 UDP 1194）
# 若 443 已被 nginx/Caddy 占用，需先调整反代或改用多路复用后再启动本服务
set -e

cd /root
PORT=443
DIR=/etc/openvpn/server
DIR_TCP=/etc/openvpn/server-tcp

# 若已有 TCP 则跳过
if [ -d "$DIR_TCP" ]; then
  echo "TCP 已存在"
  ls -la "$DIR_TCP"
  # 生成 android-tcp 客户端
  if [ ! -f /root/android-tcp.ovpn ]; then
    cd "$DIR_TCP/easy-rsa"
    ./easyrsa --batch --days=3650 build-client-full android-tcp nopass 2>/dev/null || true
    grep -vh '^#' "$DIR_TCP/client-common.txt" "$DIR_TCP/easy-rsa/pki/inline/private/android-tcp.inline" 2>/dev/null > /root/android-tcp.ovpn || \
    cat "$DIR_TCP/client-common.txt" "$DIR_TCP/easy-rsa/pki/private/android-tcp.key" "$DIR_TCP/easy-rsa/pki/issued/android-tcp.crt" "$DIR/ca.crt" > /root/android-tcp.ovpn 2>/dev/null || true
  fi
  [ -f /root/android-tcp.ovpn ] && base64 -w 0 /root/android-tcp.ovpn && echo ""
  exit 0
fi

# 复制 UDP 配置到 TCP
mkdir -p "$DIR_TCP"
cp -r "$DIR/easy-rsa" "$DIR_TCP/" 2>/dev/null || mkdir -p "$DIR_TCP/easy-rsa"
for f in ca.crt ca.key server.crt server.key dh.pem tc.key crl.pem; do
  [ -f "$DIR/$f" ] && cp "$DIR/$f" "$DIR_TCP/"
done

# 获取服务器 IP
IP=$(grep -oP 'remote \K[0-9.]+' "$DIR/client-common.txt" 2>/dev/null || ip -4 addr | grep inet | grep -vE '127\.' | head -1 | grep -oP 'inet \K[0-9.]+')
[ -z "$IP" ] && IP=$(hostname -I | awk '{print $1}')

# 创建 TCP server.conf
cat > "$DIR_TCP/server.conf" << EOF
local 0.0.0.0
port $PORT
proto tcp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-crypt tc.key
crl-verify crl.pem
server 10.8.1.0 255.255.255.0
topology subnet
mssfix 1400
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
cipher AES-256-GCM
auth SHA512
user nobody
group nogroup
persist-key
persist-tun
verb 3
EOF

# client-common for TCP
echo "client
dev tun
proto tcp
remote $IP $PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA512
ignore-unknown-option block-outside-dns
verb 3" > "$DIR_TCP/client-common.txt"

# 复制 easy-rsa 结构
[ -d "$DIR/easy-rsa" ] && cp -r "$DIR/easy-rsa" "$DIR_TCP/" 2>/dev/null || true

# 生成 android-tcp 客户端证书
cd "$DIR_TCP"
[ -d easy-rsa ] && cd easy-rsa && ./easyrsa --batch --days=3650 build-client-full android-tcp nopass 2>/dev/null || true
cd /root

# 构建客户端配置 - 使用现有 android 证书若 android-tcp 不存在
if [ -f "$DIR_TCP/easy-rsa/pki/issued/android-tcp.crt" ]; then
  grep -vh '^#' "$DIR_TCP/client-common.txt" "$DIR_TCP/easy-rsa/pki/inline/private/android-tcp.inline" 2>/dev/null > /root/android-tcp.ovpn || {
    ( cat "$DIR_TCP/client-common.txt"
      echo "<cert>"
      cat "$DIR_TCP/easy-rsa/pki/issued/android-tcp.crt"
      echo "</cert>"
      echo "<key>"
      cat "$DIR_TCP/easy-rsa/pki/private/android-tcp.key"
      echo "</key>"
      echo "<ca>"
      cat "$DIR_TCP/ca.crt"
      echo "</ca>"
      echo "<tls-crypt>"
      cat "$DIR_TCP/tc.key"
      echo "</tls-crypt>"
    ) > /root/android-tcp.ovpn
  }
elif [ -f "$DIR/easy-rsa/pki/issued/android.crt" ]; then
  # 复用 android 证书
  ( cat "$DIR_TCP/client-common.txt"
    echo "<cert>"
    cat "$DIR/easy-rsa/pki/issued/android.crt"
    echo "</cert>"
    echo "<key>"
    cat "$DIR/easy-rsa/pki/private/android.key"
    echo "</key>"
    echo "<ca>"
    cat "$DIR_TCP/ca.crt"
    echo "</ca>"
    echo "<tls-crypt>"
    cat "$DIR_TCP/tc.key"
    echo "</tls-crypt>"
  ) > /root/android-tcp.ovpn
else
  # 用 client 证书
  for c in android client; do
    [ -f "$DIR/easy-rsa/pki/issued/$c.crt" ] && {
      ( cat "$DIR_TCP/client-common.txt"
        echo "<cert>"
        cat "$DIR/easy-rsa/pki/issued/$c.crt"
        echo "</cert>"
        echo "<key>"
        cat "$DIR/easy-rsa/pki/private/$c.key"
        echo "</key>"
        echo "<ca>"
        cat "$DIR_TCP/ca.crt"
        echo "</ca>"
        echo "<tls-crypt>"
        cat "$DIR_TCP/tc.key"
        echo "</tls-crypt>"
      ) > /root/android-tcp.ovpn
      break
    }
  done
fi

# 生成 tc.key 若不存在
[ ! -f "$DIR_TCP/tc.key" ] && [ -f "$DIR/tc.key" ] && cp "$DIR/tc.key" "$DIR_TCP/"

# systemd 服务（WorkingDirectory 确保 tc.key 等相对路径可被找到）
cat > /etc/systemd/system/openvpn-server@server-tcp.service << EOF
[Unit]
After=network.target
[Service]
Type=simple
WorkingDirectory=$DIR_TCP
ExecStart=/usr/sbin/openvpn --status /run/openvpn-server/status-server-tcp.log --status-version 2 --suppress-timestamps --config $DIR_TCP/server.conf
ExecReload=/bin/kill --signal HUP \$MAINPID
CapabilityBypass=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SETGID CAP_SETUID CAP_SYS_CHROOT CAP_DAC_OVERRIDE CAP_AUDIT_WRITE
LimitNPROC=10
DeviceAllow=/dev/null rw
DeviceAllow=/dev/net/tun rw
RuntimeDirectory=openvpn-server
RuntimeDirectoryMode=0755
[Install]
WantedBy=multi-user.target
EOF

# iptables and ufw for 443
iptables -I INPUT -p tcp --dport $PORT -j ACCEPT 2>/dev/null || true
ufw allow $PORT/tcp 2>/dev/null || true
iptables -I FORWARD -s 10.8.1.0/24 -j ACCEPT 2>/dev/null || true
iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -t nat -A POSTROUTING -s 10.8.1.0/24 ! -d 10.8.1.0/24 -j MASQUERADE 2>/dev/null || true

systemctl daemon-reload
systemctl enable --now openvpn-server@server-tcp.service 2>/dev/null || true

echo "OpenVPN TCP $PORT 已启动"
ss -tlnp | grep $PORT
[ -f /root/android-tcp.ovpn ] && base64 -w 0 /root/android-tcp.ovpn && echo ""
