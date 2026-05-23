# 在 HK/US 服务器部署 OpenVPN

当前 Android 应用使用 OpenVPN 协议。我们的 HK (38.76.194.13) 和 US (154.9.26.253) 服务器已加入应用列表，但需在服务器上部署 OpenVPN 后才能连接。

## 部署步骤（每台服务器执行一次）

### 1. SSH 连接（VPN 开启时需先添加路由）

```powershell
# 管理员 PowerShell
route add 38.76.194.13 mask 255.255.255.255 192.168.0.8 metric 1
route add 154.9.26.253 mask 255.255.255.255 192.168.0.8 metric 1
```

### 2. 在服务器上运行 OpenVPN 安装脚本

**香港 (38.76.194.13):**
```bash
ssh root@38.76.194.13
# 或 plink -pw "DtrT4XnmtBwG" root@38.76.194.13

wget https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh -O openvpn-install.sh
chmod +x openvpn-install.sh
./openvpn-install.sh
# 按提示：IP 自动检测，端口 1194，协议 UDP，DNS 选 1
# 完成后输入客户端名如 "android" 生成配置
# 配置在 /root/android.ovpn
```

**美国 (154.9.26.253):**
```bash
ssh root@154.9.26.253
# 同上
```

### 3. 获取客户端配置并更新应用

在服务器上执行：
```bash
base64 -w 0 /root/android.ovpn
```

将输出的 base64 字符串替换到 `lib/features/servers/data/static_servers.dart` 中对应的 `_hkOpenVpnConfigBase64` 或 `_usOpenVpnConfigBase64`。

### 4. 重新构建应用

```bash
flutter clean && flutter pub get && flutter run -d <设备ID>
```
