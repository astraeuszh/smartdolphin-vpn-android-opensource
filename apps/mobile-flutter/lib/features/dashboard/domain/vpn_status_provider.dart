import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/vpn/models/vpn_status.dart' as model;
import '../../../services/vpn/vpn_provider.dart';

/// 当前 VPN 连接状态（含 byteIn/byteOut 累计流量）
final vpnStatusStreamProvider = StreamProvider<model.VpnStatus>((ref) {
  return ref.watch(openVpnPortProvider).statusStream;
});
