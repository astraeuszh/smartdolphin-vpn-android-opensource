# 检查 HK/US 服务器 OpenVPN 状态
# 用法: .\check-openvpn-servers.ps1

$hkHost = "38.76.194.13"
$usHost = "154.9.26.253"

$checkScript = @'
echo "=== OpenVPN 服务状态 ==="
systemctl status openvpn-server@server 2>/dev/null || systemctl status openvpn@server 2>/dev/null || echo "OpenVPN service not found"
echo ""
echo "=== 监听端口 (UDP 1194) ==="
ss -ulnp | grep 1194 || netstat -ulnp 2>/dev/null | grep 1194 || echo "UDP 1194 not listening"
echo ""
echo "=== OpenVPN 配置文件 ==="
ls -la /etc/openvpn/server/*.conf 2>/dev/null || ls -la /etc/openvpn/*.conf 2>/dev/null || echo "No config found"
echo ""
echo "=== 客户端配置是否存在 ==="
ls -la /root/android.ovpn /root/client.ovpn 2>/dev/null || echo "No client config"
'@

Write-Host "`n========== 香港服务器 $hkHost ==========" -ForegroundColor Cyan
try {
    $checkScript | plink -ssh -batch root@$hkHost "bash -s" 2>&1
} catch {
    Write-Host "SSH 失败: $_" -ForegroundColor Red
    Write-Host "请确保: 1) 已添加路由 2) plink 已安装 3) 服务器可访问"
}

Write-Host "`n========== 美国服务器 $usHost ==========" -ForegroundColor Cyan
try {
    $checkScript | plink -ssh -batch root@$usHost "bash -s" 2>&1
} catch {
    Write-Host "SSH 失败: $_" -ForegroundColor Red
}
