import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/runtime_platform.dart';
import '../../platform/android/background_keep_alive.dart';
import '../storage/prefs.dart';

const _kBatteryExemptionPrompted = 'vpn_battery_exemption_prompted_v1';

/// 首次成功连上 VPN 后引导一次「忽略电池优化」，减少进程被系统杀概率；已豁免或已提示过则不再弹系统页。
Future<void> maybeRequestBatteryExemptionOnce(Ref ref) async {
  if (!isAndroidNative) {
    return;
  }
  final prefs = await ref.read(prefsStoreProvider.future);
  if (prefs.getBool(_kBatteryExemptionPrompted)) {
    return;
  }
  if (await isIgnoringBatteryOptimizations()) {
    await prefs.setBool(_kBatteryExemptionPrompted, true);
    return;
  }
  await requestBatteryOptimizationExemption();
  await prefs.setBool(_kBatteryExemptionPrompted, true);
}
