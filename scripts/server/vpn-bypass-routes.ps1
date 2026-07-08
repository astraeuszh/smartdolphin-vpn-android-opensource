# VPN 开启时添加绕过路由，让 Flutter/ADB 能正常连接手机
# 需以管理员身份运行 PowerShell，然后执行: .\vpn-bypass-routes.ps1

$gateway = "192.168.0.8"  # 你的 WLAN 网关，如不同请修改

Write-Host "添加 VPN 绕过路由（网关: $gateway）..." -ForegroundColor Cyan

# 本地局域网 - 手机 WiFi 调试、ADB 等
route add 192.168.0.0 mask 255.255.0.0 $gateway metric 1
if ($LASTEXITCODE -eq 0) { Write-Host "  [OK] 192.168.0.0/16 -> 本地网络" -ForegroundColor Green } else { Write-Host "  [跳过] 192.168.0.0/16 可能已存在" -ForegroundColor Yellow }

# 10.x 局域网（部分路由器用此网段）
route add 10.0.0.0 mask 255.0.0.0 $gateway metric 1
if ($LASTEXITCODE -eq 0) { Write-Host "  [OK] 10.0.0.0/8 -> 本地网络" -ForegroundColor Green } else { Write-Host "  [跳过] 10.0.0.0/8" -ForegroundColor Yellow }

# Gradle/Maven 下载（如 build 仍失败可取消注释）
# $gradleIP = (Resolve-DnsName services.gradle.org -Type A -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
# if ($gradleIP) { route add $gradleIP mask 255.255.255.255 $gateway metric 1; Write-Host "  [OK] services.gradle.org -> $gradleIP" -ForegroundColor Green }

Write-Host "`n完成。Flutter run 和 ADB 现在应能连接手机。" -ForegroundColor Green
Write-Host "若网关不是 $gateway，请用 ipconfig 查看默认网关并修改脚本。" -ForegroundColor Gray
