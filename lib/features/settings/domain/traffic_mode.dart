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
    this.compiledSourceHash = '',
    this.savedRuleName = '',
    this.pendingReconnect = false,
  });

  final RuleSource source;
  final String customRules;
  /// SHA256 hash from last successful SDRL compile (`sha256:…`).
  final String compiledSourceHash;
  /// User-chosen file name (without .sdrl). Empty = never saved to library.
  final String savedRuleName;
  /// Rule changed while VPN connected — reconnect to apply.
  final bool pendingReconnect;

  RuleDatabase copyWith({
    RuleSource? source,
    String? customRules,
    String? compiledSourceHash,
    String? savedRuleName,
    bool? pendingReconnect,
  }) =>
      RuleDatabase(
        source: source ?? this.source,
        customRules: customRules ?? this.customRules,
        compiledSourceHash: compiledSourceHash ?? this.compiledSourceHash,
        savedRuleName: savedRuleName ?? this.savedRuleName,
        pendingReconnect: pendingReconnect ?? this.pendingReconnect,
      );

  /// Built-in China IP list (17mon — well-known GitHub project).
  static const builtInUrls = [
    'https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt',
    'https://cdn.jsdelivr.net/gh/17mon/china_ip_list@master/china_ip_list.txt',
  ];

  Map<String, dynamic> toJson() => {
        'source': source.name,
        'customRules': customRules,
        'compiledSourceHash': compiledSourceHash,
        'savedRuleName': savedRuleName,
        'pendingReconnect': pendingReconnect,
      };

  factory RuleDatabase.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RuleDatabase();
    return RuleDatabase(
      source: RuleSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => RuleSource.builtIn,
      ),
      customRules: json['customRules'] as String? ?? '',
      compiledSourceHash: json['compiledSourceHash'] as String? ?? '',
      savedRuleName: json['savedRuleName'] as String? ?? '',
      pendingReconnect: json['pendingReconnect'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props =>
      [source, customRules, compiledSourceHash, savedRuleName, pendingReconnect];
}
