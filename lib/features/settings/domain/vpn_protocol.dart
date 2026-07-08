import 'package:smartdolphin_vpn/core/utils/iterable_extensions.dart';
import 'package:smartdolphin_vpn/l10n/app_localizations.dart';

enum VpnProtocol { wireGuard, openVpn, ikev2 }

enum VpnDnsOption { google, cloudflare, dns114, quad9, custom }

extension VpnProtocolX on VpnProtocol {
  String get label {
    switch (this) {
      case VpnProtocol.wireGuard:
        return 'WireGuard';
      case VpnProtocol.openVpn:
        return 'OpenVPN';
      case VpnProtocol.ikev2:
        return 'IKEv2/IPsec';
    }
  }

  bool get isSupported => true;
}

extension VpnDnsOptionX on VpnDnsOption {
  String labelFor(AppLocalizations l10n) {
    switch (this) {
      case VpnDnsOption.google:
        return l10n.settingsDnsGoogle;
      case VpnDnsOption.cloudflare:
        return l10n.settingsDnsCloudflare;
      case VpnDnsOption.dns114:
        return l10n.settingsDns114;
      case VpnDnsOption.quad9:
        return l10n.settingsDnsQuad9;
      case VpnDnsOption.custom:
        return l10n.settingsDnsCustom;
    }
  }
}

VpnProtocol protocolFromName(String? name) {
  return VpnProtocol.values.firstWhereOrNull((p) => p.name == name) ??
      VpnProtocol.wireGuard;
}

VpnDnsOption dnsOptionFromName(String? name) {
  if (name == 'custom') {
    return VpnDnsOption.custom;
  }
  return VpnDnsOption.values.firstWhereOrNull((p) => p.name == name) ??
      VpnDnsOption.google;
}
