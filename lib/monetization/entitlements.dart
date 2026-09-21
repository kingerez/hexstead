import 'package:hexstead_engine/hexstead_engine.dart';

/// The single non-consumable unlock. Must match the product created in
/// App Store Connect and Play Console exactly.
const String fullUnlockProductId = 'hexstead.full';

/// SharedPreferences key caching the entitlement so offline launches keep
/// the unlock. The store's answer wins over this cache when available.
const String unlockedCacheKey = 'unlocked_v1';

/// SharedPreferences key counting real games started via the setup screen.
/// The tutorial never passes through setup, so it never increments this.
const String gamesStartedKey = 'games_started_v1';

/// Free tier is exactly one easy bot; the unlock opens everything else.
bool setupChoiceAllowed({
  required bool unlocked,
  required int botCount,
  required BotDifficulty difficulty,
}) =>
    unlocked || (botCount == 1 && difficulty == BotDifficulty.easy);

/// The pre-game interstitial: free players only, and never before their
/// first real game - the first session stays clean.
bool shouldShowInterstitial({
  required bool unlocked,
  required int gamesStartedBefore,
}) =>
    !unlocked && gamesStartedBefore >= 1;
