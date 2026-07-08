/// 传输协议：3 个单协议 + 3 个组合协议。
enum TransportProtocol {
  wireGuard,
  openVpn,
  ikev2,
  wireGuardOpenVpn,
  wireGuardIkev2,
  openVpnIkev2,
}

extension TransportProtocolX on TransportProtocol {
  bool get isCombo =>
      this == TransportProtocol.wireGuardOpenVpn ||
      this == TransportProtocol.wireGuardIkev2 ||
      this == TransportProtocol.openVpnIkev2;

  /// OpenVPN 隧道层是否参与（当前节点均通过 OpenVPN 承载）。
  bool get usesOpenVpn =>
      this == TransportProtocol.openVpn ||
      this == TransportProtocol.wireGuardOpenVpn ||
      this == TransportProtocol.openVpnIkev2;

  bool get usesWireGuardProfile =>
      this == TransportProtocol.wireGuard ||
      this == TransportProtocol.wireGuardOpenVpn ||
      this == TransportProtocol.wireGuardIkev2;

  bool get usesIkev2Profile =>
      this == TransportProtocol.ikev2 ||
      this == TransportProtocol.wireGuardIkev2 ||
      this == TransportProtocol.openVpnIkev2;

  String labelZh() {
    return switch (this) {
      TransportProtocol.wireGuard => 'WireGuard（最快速）',
      TransportProtocol.openVpn => 'OpenVPN',
      TransportProtocol.ikev2 => 'IKEv2/IPsec（最安全）',
      TransportProtocol.wireGuardOpenVpn => 'WireGuard + OpenVPN（最推荐）',
      TransportProtocol.wireGuardIkev2 => 'WireGuard + IKEv2',
      TransportProtocol.openVpnIkev2 => 'OpenVPN + IKEv2',
    };
  }

  String labelEn() {
    return switch (this) {
      TransportProtocol.wireGuard => 'WireGuard (fastest)',
      TransportProtocol.openVpn => 'OpenVPN',
      TransportProtocol.ikev2 => 'IKEv2/IPsec (most secure)',
      TransportProtocol.wireGuardOpenVpn => 'WireGuard + OpenVPN (recommended)',
      TransportProtocol.wireGuardIkev2 => 'WireGuard + IKEv2',
      TransportProtocol.openVpnIkev2 => 'OpenVPN + IKEv2',
    };
  }
}

TransportProtocol transportProtocolFromName(String? name) {
  if (name == null || name.isEmpty) return TransportProtocol.openVpn;
  // 兼容旧版存储
  const legacy = {
    'realityVless': TransportProtocol.openVpn,
    'hysteria2': TransportProtocol.wireGuard,
    'tuic': TransportProtocol.ikev2,
  };
  if (legacy.containsKey(name)) return legacy[name]!;
  for (final p in TransportProtocol.values) {
    if (p.name == name) return p;
  }
  return TransportProtocol.openVpn;
}
