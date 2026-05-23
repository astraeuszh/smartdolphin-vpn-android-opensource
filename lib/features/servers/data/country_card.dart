import '../domain/server.dart';

/// Represents a country/region card for server selection display.
class CountryCard {
  const CountryCard({
    required this.countryCode,
    required this.countryName,
    this.server,
    this.latencyMs,
    this.isPinned = false,
  });

  final String countryCode;
  final String countryName;
  final Server? server;
  final int? latencyMs;
  final bool isPinned;

  bool get isConnectable =>
      server != null && (latencyMs == null || latencyMs! <= 800);

  bool get isLatencyTimeout =>
      latencyMs != null && (latencyMs! > 800 || latencyMs! == 9999);

  CountryCard copyWith({Server? server, int? latencyMs}) {
    return CountryCard(
      countryCode: countryCode,
      countryName: countryName,
      server: server ?? this.server,
      latencyMs: latencyMs ?? this.latencyMs,
      isPinned: isPinned,
    );
  }
}
