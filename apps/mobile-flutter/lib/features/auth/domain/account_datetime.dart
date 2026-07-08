import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';

/// Matches sd-server permanent subscription marker (2100-01-01 UTC).
const kPermanentExpireUnix = 4102444800;

const kTrialDurationSec = 86400;

String formatAccountDateTime(
  int unixSec, {
  required String localeTag,
  required AppLocalizations l10n,
}) {
  if (unixSec <= 0) {
    return l10n.accountDateTimeNone;
  }
  if (unixSec >= kPermanentExpireUnix) {
    return l10n.accountDateTimePermanent;
  }
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000, isUtc: true).toLocal();
  final pattern = localeTag.startsWith('zh')
      ? 'yyyy年MM月dd日 HH:mm:ss'
      : 'yyyy-MM-dd HH:mm:ss';
  return DateFormat(pattern).format(dt);
}

String formatTrialRemaining(int expireAtUnix, AppLocalizations l10n) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final sec = (expireAtUnix - now).clamp(0, kTrialDurationSec * 2);
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  return l10n.authTrialRemaining(h, m, s);
}