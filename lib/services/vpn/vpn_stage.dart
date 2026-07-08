/// Connection stages emitted by the VPN port. Replaces the old
/// `openvpn_flutter` VPNStage so the app no longer depends on OpenVPN.
/// Names/values are kept compatible with the previous consumers.
enum VPNStage {
  prepare,
  authenticating,
  connecting,
  connected,
  disconnected,
  disconnecting,
  waitConnection,
  reconnect,
  noConnection,
  denied,
  error,
  exiting,
  unknown,
}

VPNStage vpnStageFromString(String? raw) {
  switch ((raw ?? '').toLowerCase().replaceAll(' ', '_')) {
    case 'prepare':
      return VPNStage.prepare;
    case 'authenticating':
      return VPNStage.authenticating;
    case 'connecting':
    case 'tcp_connect':
    case 'udp_connect':
    case 'assign_ip':
    case 'resolve':
    case 'get_config':
    case 'vpn_generate_config':
      return VPNStage.connecting;
    case 'connected':
      return VPNStage.connected;
    case 'disconnected':
      return VPNStage.disconnected;
    case 'disconnecting':
      return VPNStage.disconnecting;
    case 'wait_connection':
      return VPNStage.waitConnection;
    case 'reconnect':
      return VPNStage.reconnect;
    case 'no_connection':
      return VPNStage.noConnection;
    case 'denied':
      return VPNStage.denied;
    case 'error':
      return VPNStage.error;
    case 'exiting':
      return VPNStage.exiting;
    default:
      return VPNStage.unknown;
  }
}
