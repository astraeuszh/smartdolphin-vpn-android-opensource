import 'package:equatable/equatable.dart';

enum SpeedTestStatus { idle, preparing, running, complete, error }

enum SpeedTestPhase { idle, locating, ping, download, upload }

typedef SpeedSeries = List<double>;

class SpeedTestState extends Equatable {
  const SpeedTestState({
    required this.status,
    this.phase = SpeedTestPhase.idle,
    this.ping,
    this.downloadMbps = 0,
    this.uploadMbps = 0,
    this.liveMbps = 0,
    this.ip,
    this.serverName,
    this.errorMessage,
    this.downloadSeries = const [],
    this.uploadSeries = const [],
    this.lastRun,
    this.isVpnTest = false,
  });

  factory SpeedTestState.initial() => const SpeedTestState(status: SpeedTestStatus.idle);

  final SpeedTestStatus status;
  final SpeedTestPhase phase;
  final Duration? ping;
  final double downloadMbps;
  final double uploadMbps;
  final double liveMbps;
  final String? ip;
  final String? serverName;
  final String? errorMessage;
  final SpeedSeries downloadSeries;
  final SpeedSeries uploadSeries;
  final DateTime? lastRun;
  /// true = VPN 隧道测速, false = 本地网络测速
  final bool isVpnTest;

  double get gaugeMax {
    final peak = [
      liveMbps,
      downloadMbps,
      uploadMbps,
      if (downloadSeries.isNotEmpty) downloadSeries.reduce((a, b) => a > b ? a : b),
      if (uploadSeries.isNotEmpty) uploadSeries.reduce((a, b) => a > b ? a : b),
    ].fold<double>(0, (max, value) => value > max ? value : max);
    if (peak <= 0) return 180;
    if (peak <= 50) return 50;
    if (peak <= 100) return 100;
    if (peak <= 180) return 180;
    if (peak <= 300) return 300;
    return ((peak / 100).ceil() * 100).toDouble();
  }

  double get gaugeValue {
    if (phase == SpeedTestPhase.upload && liveMbps > 0) return liveMbps;
    if (phase == SpeedTestPhase.download && liveMbps > 0) return liveMbps;
    if (status == SpeedTestStatus.complete) return downloadMbps;
    if (status == SpeedTestStatus.running && liveMbps > 0) return liveMbps;
    return 0;
  }

  int get networkScore {
    if (!hasResult && downloadMbps <= 0 && uploadMbps <= 0) return 0;
    final dlScore = (downloadMbps / 100 * 50).clamp(0, 50);
    final ulScore = (uploadMbps / 40 * 25).clamp(0, 25);
    final pingMs = ping?.inMilliseconds;
    final pingScore = pingMs == null
        ? 12.5
        : pingMs <= 40
            ? 25.0
            : pingMs <= 80
                ? 18.0
                : pingMs <= 150
                    ? 10.0
                    : 0.0;
    return (dlScore + ulScore + pingScore).round().clamp(0, 100);
  }

  bool get isBusy =>
      status == SpeedTestStatus.running || status == SpeedTestStatus.preparing;

  bool get hasResult => status == SpeedTestStatus.complete &&
      (downloadSeries.isNotEmpty || uploadSeries.isNotEmpty || ping != null);

  SpeedTestState copyWith({
    SpeedTestStatus? status,
    SpeedTestPhase? phase,
    Duration? ping,
    double? downloadMbps,
    double? uploadMbps,
    double? liveMbps,
    String? ip,
    String? serverName,
    String? errorMessage,
    SpeedSeries? downloadSeries,
    SpeedSeries? uploadSeries,
    DateTime? lastRun,
    bool? isVpnTest,
  }) {
    return SpeedTestState(
      status: status ?? this.status,
      phase: phase ?? this.phase,
      ping: ping ?? this.ping,
      downloadMbps: downloadMbps ?? this.downloadMbps,
      uploadMbps: uploadMbps ?? this.uploadMbps,
      liveMbps: liveMbps ?? this.liveMbps,
      ip: ip ?? this.ip,
      serverName: serverName ?? this.serverName,
      errorMessage: errorMessage,
      downloadSeries: downloadSeries ?? this.downloadSeries,
      uploadSeries: uploadSeries ?? this.uploadSeries,
      lastRun: lastRun ?? this.lastRun,
      isVpnTest: isVpnTest ?? this.isVpnTest,
    );
  }

  @override
  List<Object?> get props => [
        status,
        phase,
        ping,
        downloadMbps,
        uploadMbps,
        liveMbps,
        ip,
        serverName,
        errorMessage,
        downloadSeries,
        uploadSeries,
        lastRun,
        isVpnTest,
      ];
}
