/// Max VPN session wall-clock span (elapsedRealtime-based). Timer UI freezes at this value.
const Duration kMaxSessionWallDuration = Duration(
  days: 99,
  hours: 23,
  minutes: 59,
  seconds: 59,
  milliseconds: 999,
);

int get kMaxSessionDurationMs => kMaxSessionWallDuration.inMilliseconds;
