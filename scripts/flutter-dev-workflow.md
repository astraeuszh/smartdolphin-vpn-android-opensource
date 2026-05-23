# Flutter 开发流程 - 无需每次重装

## 热重载：改完代码立刻看到效果

**不需要每次改完都重新安装！** 用下面方式开发：

### 1. 手机连电脑（USB），开启 USB 调试

### 2. 运行一次（会安装到手机）
```powershell
cd Z:\SmartDolphinVPN\SmartDolphinVPNAndroid
C:\flutter\bin\flutter.bat run -d <设备ID>
```

设备 ID 可用 `flutter devices` 查看，例如 `3B1F5DE5MS120VL1`。

### 3. 保持终端开着，改代码后按键盘
- **`r`** = 热重载（约 1 秒，界面立刻更新）
- **`R`** = 热重启（重新跑一遍 app）
- **`q`** = 退出

改按钮、改文字、改布局 → 按 `r` → 手机上的 app 马上更新，**不用重装**。

### 4. 什么时候需要重新安装？
只有这些情况才需要重新 `flutter run`：
- 改了 `pubspec.yaml`（新依赖）
- 改了 `AndroidManifest.xml`、Gradle 等原生配置
- 改了 `main()` 入口逻辑

普通 Dart 代码、UI、文案 → 热重载即可。

---

## VPN 开着时网络有问题？

运行 `scripts/vpn-bypass-routes.ps1`（需管理员权限），让本地网络流量不走 VPN，ADB 就能连上手机。
