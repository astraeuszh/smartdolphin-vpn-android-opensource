import 'package:flutter_test/flutter_test.dart';

import 'package:smartdolphin_vpn/features/history/presentation/history_screen.dart';

void main() {
  test('format duration provides hours and minutes', () {
    final result = formatHistoryDuration(const Duration(hours: 2, minutes: 15));
    expect(result, '2h 15m');
  });
}
