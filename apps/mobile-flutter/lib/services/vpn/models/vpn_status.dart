/// VPN connection status snapshot used for UI/notification updates.
class VpnStatus {
  const VpnStatus({
    required this.duration,
    this.connectedOn,
    required this.byteIn,
    required this.byteOut,
    required this.packetsIn,
    required this.packetsOut,
    this.byteInRate = '0',
    this.byteOutRate = '0',
  });

  final String duration;
  final DateTime? connectedOn;
  final String byteIn;
  final String byteOut;
  final String packetsIn;
  final String packetsOut;

  /// Instantaneous throughput in bytes/sec, straight from the core's status
  /// stream (libbox StatusMessage.downlink/uplink). Far more reliable than
  /// deriving deltas from the cumulative counters.
  final String byteInRate;
  final String byteOutRate;

  factory VpnStatus.empty() => const VpnStatus(
        duration: '00:00:00',
        connectedOn: null,
        byteIn: '0',
        byteOut: '0',
        packetsIn: '0',
        packetsOut: '0',
        byteInRate: '0',
        byteOutRate: '0',
      );

  Map<String, dynamic> toJson() {
    return {
      'duration': duration,
      'connected_on': connectedOn?.toIso8601String(),
      'byte_in': byteIn,
      'byte_out': byteOut,
      'packets_in': packetsIn,
      'packets_out': packetsOut,
      'byte_in_rate': byteInRate,
      'byte_out_rate': byteOutRate,
    };
  }

  VpnStatus copyWith({
    String? duration,
    DateTime? connectedOn,
    String? byteIn,
    String? byteOut,
    String? packetsIn,
    String? packetsOut,
    String? byteInRate,
    String? byteOutRate,
  }) {
    return VpnStatus(
      duration: duration ?? this.duration,
      connectedOn: connectedOn ?? this.connectedOn,
      byteIn: byteIn ?? this.byteIn,
      byteOut: byteOut ?? this.byteOut,
      packetsIn: packetsIn ?? this.packetsIn,
      packetsOut: packetsOut ?? this.packetsOut,
      byteInRate: byteInRate ?? this.byteInRate,
      byteOutRate: byteOutRate ?? this.byteOutRate,
    );
  }

  @override
  String toString() {
    return 'VpnStatus(duration: $duration, byteIn: $byteIn, byteOut: $byteOut)';
  }
}
