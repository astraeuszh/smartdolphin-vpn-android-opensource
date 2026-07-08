import 'package:intl/intl.dart';

import '../session/session_limits.dart';

String formatCountdown(Duration duration) {
  return formatNotificationDuration(duration);
}

/// Format elapsed time as MM:SS (e.g. 00:01, 00:02).
String formatElapsed(Duration duration) {
  return formatNotificationDuration(duration);
}

/// Compact session timer: `X时 X分 X秒`, auto prepends days after 24h.
String formatSessionElapsedCompact(Duration raw) {
  final d = _capSessionDuration(raw);
  final totalSeconds = d.inSeconds;
  final days = totalSeconds ~/ 86400;
  final rem = totalSeconds % 86400;
  final hours = rem ~/ 3600;
  final minutes = (rem % 3600) ~/ 60;
  final seconds = rem % 60;

  if (days > 0) {
    return '${days}天 ${hours}时 ${minutes}分 ${seconds}秒';
  }
  return '${hours}时 ${minutes}分 ${seconds}秒';
}

/// Precise session timer: always shows day/hour/min/sec/ms segments.
String formatSessionElapsedPrecise(Duration raw) {
  final d = _capSessionDuration(raw);
  final ms = d.inMilliseconds % 1000;
  var t = d.inMilliseconds ~/ 1000;
  final sec = t % 60;
  t ~/= 60;
  final min = t % 60;
  t ~/= 60;
  final hour = t % 24;
  final day = t ~/ 24;
  return '${day}天 ${hour}时 ${min}分 ${sec}秒 ${ms.toString().padLeft(3, '0')}毫秒';
}

Duration _capSessionDuration(Duration raw) {
  final cap = kMaxSessionWallDuration;
  if (raw.isNegative) return Duration.zero;
  return raw > cap ? cap : raw;
}


String formatNotificationDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final totalSeconds = safe.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final minutesString = minutes.toString().padLeft(2, '0');
  final secondsString = seconds.toString().padLeft(2, '0');

  if (hours > 0) {
    final hoursString = hours.toString().padLeft(2, '0');
    return '$hoursString:$minutesString:$secondsString';
  }

  return '$minutesString:$secondsString';
}

String formatDateTime(DateTime dateTime) {
  final formatter = DateFormat('yMMMd HH:mm');
  return formatter.format(dateTime.toLocal());
}
