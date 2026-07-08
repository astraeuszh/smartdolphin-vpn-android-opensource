import 'package:equatable/equatable.dart';

class PreferencesState extends Equatable {
  static const Object _sentinel = Object();
  static const defaultLocaleCode = 'en';
  /// Persisted when user picks "follow system" in settings.
  static const systemLocaleCode = '__system__';

  const PreferencesState({
    this.autoServerSwitch = true,
    this.hapticsEnabled = true,
    this.localeCode = defaultLocaleCode,
    this.privacyPolicyAccepted = false,
    this.onboardingCompleted = false,
    this.autoReconnect = false,
    this.coreProtocol = 'reality',
  });

  final bool autoServerSwitch;
  final bool hapticsEnabled;
  final String? localeCode;
  final bool privacyPolicyAccepted;
  final bool onboardingCompleted;
  final bool autoReconnect;
  /// Dolphin-Core transport: 'reality' | 'hysteria2' | 'wireguard'.
  final String coreProtocol;

  PreferencesState copyWith({
    bool? autoServerSwitch,
    bool? hapticsEnabled,
    Object? localeCode = _sentinel,
    bool? privacyPolicyAccepted,
    bool? onboardingCompleted,
    bool? autoReconnect,
    String? coreProtocol,
  }) {
    return PreferencesState(
      autoServerSwitch: autoServerSwitch ?? this.autoServerSwitch,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      localeCode:
          identical(localeCode, _sentinel) ? this.localeCode : localeCode as String?,
      privacyPolicyAccepted: privacyPolicyAccepted ?? this.privacyPolicyAccepted,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      coreProtocol: coreProtocol ?? this.coreProtocol,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'autoServerSwitch': autoServerSwitch,
      'hapticsEnabled': hapticsEnabled,
      'localeCode': localeCode ?? systemLocaleCode,
      'privacyPolicyAccepted': privacyPolicyAccepted,
      'onboardingCompleted': onboardingCompleted,
      'autoReconnect': autoReconnect,
      'coreProtocol': coreProtocol,
    };
  }

  factory PreferencesState.fromJson(Map<String, dynamic> json) {
    return PreferencesState(
      autoServerSwitch: json['autoServerSwitch'] as bool? ?? true,
      hapticsEnabled: json['hapticsEnabled'] as bool? ?? true,
      localeCode: _parseLocaleCode(json['localeCode'] as String?),
      privacyPolicyAccepted: json['privacyPolicyAccepted'] as bool? ?? false,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      autoReconnect: json['autoReconnect'] as bool? ?? false,
      coreProtocol: json['coreProtocol'] as String? ?? 'reality',
    );
  }

  static String? _parseLocaleCode(String? raw) {
    if (raw == null || raw.isEmpty || raw == systemLocaleCode) {
      return defaultLocaleCode;
    }
    return raw;
  }

  @override
  List<Object?> get props => [
        autoServerSwitch,
        hapticsEnabled,
        localeCode,
        privacyPolicyAccepted,
        onboardingCompleted,
        autoReconnect,
        coreProtocol,
      ];
}
