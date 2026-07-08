import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smartdolphin_vpn/app/app.dart';

void main() {
  testWidgets('SmartDolphinApp builds', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SmartDolphinApp()));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SmartDolphinApp), findsOneWidget);
  });
}
