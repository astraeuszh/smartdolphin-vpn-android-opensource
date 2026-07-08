import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_game_traffic_engine.dart';
import 'game_traffic_engine.dart';

final gameTrafficEngineProvider = Provider<GameTrafficEngine>((ref) {
  final engine = LocalGameTrafficEngine();
  ref.onDispose(() {
    unawaited(engine.stop());
  });
  return engine;
});
