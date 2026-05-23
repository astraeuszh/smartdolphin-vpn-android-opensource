# 在两台服务器上部署 OpenVPN TCP 443（与 SmartDolphin 网站 / Windows 内核统一端口）
# 注意：443 若已被 nginx/Caddy 占用，需先调整反代或改用 sslh 等多路复用，再让 OpenVPN 监听 443

param(
    [string]$HkPass = "DtrT4XnmtBwG",
    [string]$UsPass = ""  # 美国服务器密码，若为空则跳过
)

$hkHost = "38.76.194.13"
$usHost = "154.9.26.253"
$hkKey = "SHA256:lrXpFN9ZprUFxlX2h1V2eYLL5fqEkyvq4SG3TYLseGc"

$deployScript = @'
set -e
echo "=== 检查现有 OpenVPN ==="
ls -la /etc/openvpn/server/ 2>/dev/null || true

echo ""
echo "=== 安装 OpenVPN TCP 443 (不覆盖现有 UDP) ==="
cd /root
wget -q https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh -O openvpn-install.sh 2>/dev/null || curl -sL -o openvpn-install.sh https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh
chmod +x openvpn-install.sh

# 若已有 UDP 配置，添加 TCP 客户端；否则全新安装 TCP 443
if [ -f /etc/openvpn/server/server.conf ]; then
  # 检查是否已有 TCP 配置
  if grep -q "proto tcp" /etc/openvpn/server/server.conf 2>/dev/null; then
    echo "TCP 已存在，添加 android-tcp 客户端"
    printf '1\nandroid-tcp\n' | ./openvpn-install.sh
  else
    echo "现有为 UDP，需新建 TCP 实例。运行交互式安装:"
    echo "  ./openvpn-install.sh"
    echo "  选择: 2) TCP, 端口 443, 客户端名 android-tcp"
    echo "  或使用以下非交互命令 (需脚本支持):"
    # Nyr 脚本首次安装需交互，这里用 expect 或 printf 模拟
    printf '2\n443\n1\nandroid-tcp\n' | ./openvpn-install.sh 2>/dev/null || true
  fi
else
  echo "全新安装 OpenVPN TCP 443"
  # 自动选择: TCP, 443, DNS 1, 客户端 android-tcp
  printf '2\n443\n1\nandroid-tcp\n' | ./openvpn-install.sh 2>/dev/null || printf '\n\n443\n2\n1\nandroid-tcp\n' | ./openvpn-install.sh 2>/dev/null || true
fi

echo ""
echo "=== 查找 TCP 客户端配置 ==="
for f in /root/android-tcp.ovpn /root/android.ovpn /root/client.ovpn; do
  if [ -f "$f" ]; then
    # 确保配置为 TCP 443
    sed -i 's/proto udp/proto tcp/' "$f" 2>/dev/null || true
    sed -i 's/1194/443/g' "$f" 2>/dev/null || true
    echo "Found: $f"
    base64 -w 0 "$f"
    echo ""
    exit 0
  fi
done

echo "未找到 ovpn，列出 /root/*.ovpn:"
ls -la /root/*.ovpn 2>/dev/null || exit 1
'@

Write-Host "`n========== 香港服务器 $hkHost ==========" -ForegroundColor Cyan
try {
    $result = $deployScript | plink -ssh -batch -pw $HkPass -hostkey $hkKey root@$hkHost "bash -s" 2>&1
    $result
} catch {
    Write-Host "错误: $_" -ForegroundColor Red
}

if ($UsPass) {
    Write-Host "`n========== 美国服务器 $usHost ==========" -ForegroundColor Cyan
    try {
        $result = $deployScript | plink -ssh -batch -pw $UsPass root@$usHost "bash -s" 2>&1
        $result
    } catch {
        Write-Host "错误: $_" -ForegroundColor Red
    }
} else {
    Write-Host "`n跳过美国服务器 (未提供 UsPass)" -ForegroundColor Yellow
}
