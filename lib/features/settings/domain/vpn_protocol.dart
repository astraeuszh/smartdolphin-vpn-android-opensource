import 'package:smartdolphin_vpn/core/utils/iterable_extensions.dart';
import 'package:smartdolphin_vpn/l10n/app_localizations.dart';

enum VpnProtocol { wireGuard, openVpn, ikev2 }

enum VpnDnsOption { cloudflare, google }

extension VpnProtocolX on VpnProtocol {
  String get label {
    switch (this) {
      case VpnProtocol.wireGuard:
        return 'WireGuard';
      case VpnProtocol.openVpn:
        return 'OpenVPN (coming soon)';
      case VpnProtocol.ikev2:
        return 'IKEv2 (coming soon)';
    }
  }

  bool get isSupported => this == VpnProtocol.wireGuard;
}

extension VpnDnsOptionX on VpnDnsOption {
  String labelFor(AppLocalizations l10n) {
    switch (this) {
      case VpnDnsOption.cloudflare:
        return l10n.settingsDnsCloudflare;
      case VpnDnsOption.google:
        return l10n.settingsDnsGoogle;
    }
  }
}

VpnProtocol protocolFromName(String? name) {
  return VpnProtocol.values.firstWhereOrNull((p) => p.name == name) ??
      VpnProtocol.wireGuard;
}

VpnDnsOption dnsOptionFromName(String? name) {
  if (name == 'custom') {
    return VpnDnsOption.cloudflare;
  }
  return VpnDnsOption.values.firstWhereOrNull((p) => p.name == name) ??
      VpnDnsOption.cloudflare;
}
