import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Single source of truth for work that must stop while Android is backgrounded.
final appForegroundProvider = StateProvider<bool>((ref) => true);
