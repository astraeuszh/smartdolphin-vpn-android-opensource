import '../../../services/storage/prefs.dart';
import '../domain/game_decel_tier.dart';

class GameDecelTierRepository {
  GameDecelTierRepository(this._prefs);

  final PrefsStore _prefs;
  static const _key = 'game_decel_tier_v1';

  GameDecelTier load() {
    final raw = _prefs.getString(_key);
    return gameDecelTierFromStorage(raw);
  }

  Future<void> save(GameDecelTier tier) async {
    await _prefs.setString(_key, tier.toStorage());
  }
}
