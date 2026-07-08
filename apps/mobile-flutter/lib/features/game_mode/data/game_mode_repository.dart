import '../../../services/storage/prefs.dart';
import '../domain/game_mode_speed.dart';

/// 游戏模式偏好（本地「后端」持久化）
class GameModeRepository {
  GameModeRepository(this._prefs);

  final PrefsStore _prefs;
  static const _key = 'game_mode_speed_v1';

  GameModeSpeed load() {
    final raw = _prefs.getString(_key);
    return gameModeSpeedFromStorage(raw);
  }

  Future<void> save(GameModeSpeed mode) async {
    await _prefs.setString(_key, mode.toStorage());
  }
}
