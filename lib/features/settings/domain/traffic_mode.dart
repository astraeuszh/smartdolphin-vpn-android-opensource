import 'package:equatable/equatable.dart';

/// Traffic routing mode: all through VPN or rule-based split.
enum TrafficMode {
  /// All traffic through VPN tunnel.
  global,

  /// Rule-based: user custom rules required; matched routes go direct.
  rule,

  /// Built-in split: e.g. Baidu direct, rest via VPN (no TUN split app).
  auto,
}

/// Rule source: built-in China IP list from GitHub, or custom user-edited rules.
enum RuleSource {
  /// Use built-in China IP list (国内直连、国外走 VPN).
  builtIn,

  /// Use custom rules edited by user.
  custom,
}

/// Rule database: source + custom text. OpenVPN route format.
/// Built-in: fetches China CIDR list from GitHub/CDN.
/// Custom: one rule per line - CIDR (1.0.1.0/24) or domain (baidu.com).
class RuleDatabase extends Equatable {
  const RuleDatabase({
    this.source = RuleSource.builtIn,
    this.customRules = '',
  });

  final RuleSource source;
  final String customRules;

  RuleDatabase copyWith({RuleSource? source, String? customRules}) =>
      RuleDatabase(
        source: source ?? this.source,
        customRules: customRules ?? this.customRules,
      );

  /// Built-in China IP list (17mon — well-known GitHub project).
  static const builtInUrls = [
    'https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt',
    'https://cdn.jsdelivr.net/gh/17mon/china_ip_list@master/china_ip_list.txt',
  ];

  Map<String, dynamic> toJson() => {
        'source': source.name,
        'customRules': customRules,
      };

  factory RuleDatabase.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RuleDatabase();
    return RuleDatabase(
      source: RuleSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => RuleSource.builtIn,
      ),
      customRules: json['customRules'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [source, customRules];
}
