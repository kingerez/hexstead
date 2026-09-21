import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../art/art_store.dart';
import '../audio/sound_store.dart';
import '../monetization/ad_service.dart';
import '../monetization/entitlements.dart';
import '../monetization/purchase_store.dart';
import '../state/game_controller.dart';
import '../state/high_scores.dart';
import '../widgets/chrome.dart';
import '../widgets/paywall_dialog.dart';
import 'game_screen.dart';

class SetupScreen extends StatefulWidget {
  final GameController controller;

  const SetupScreen({super.key, required this.controller});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  // Free tier starts on its own allowed combination; unlocked players keep
  // the classic default of a fair 3-player game.
  late int _botCount = PurchaseStore.instance.isUnlocked ? 2 : 1;
  late BotDifficulty _difficulty = PurchaseStore.instance.isUnlocked
      ? BotDifficulty.medium
      : BotDifficulty.easy;

  static const _botNames = ['Rosalind', 'Bertram', 'Wilhelmina'];

  @override
  void initState() {
    super.initState();
    PurchaseStore.instance.addListener(_onPurchaseChanged);
    _maybePreloadAd();
  }

  @override
  void dispose() {
    PurchaseStore.instance.removeListener(_onPurchaseChanged);
    super.dispose();
  }

  /// A purchase can land while this screen is up (paywall opened from a
  /// locked chip) - the locks have to melt away without a rebuild from
  /// outside.
  void _onPurchaseChanged() {
    if (mounted) setState(() {});
  }

  /// Only fetch ad inventory when it can actually be shown: free player,
  /// past the first-game grace. Unlocked players never load the SDK's work.
  Future<void> _maybePreloadAd() async {
    if (PurchaseStore.instance.isUnlocked) return;
    final prefs = await SharedPreferences.getInstance();
    final started = prefs.getInt(gamesStartedKey) ?? 0;
    if (shouldShowInterstitial(unlocked: false, gamesStartedBefore: started)) {
      AdService.instance.preload();
    }
  }

  Future<void> _start() async {
    SoundStore.instance.playSfx(Sfx.uiTap);
    final players = [
      const PlayerSetup(name: 'You', isBot: false),
      for (var i = 0; i < _botCount; i++)
        PlayerSetup(name: _botNames[i], isBot: true, difficulty: _difficulty),
    ];
    final navigator = Navigator.of(context);
    final prefs = await SharedPreferences.getInstance();
    final startedBefore = prefs.getInt(gamesStartedKey) ?? 0;
    await prefs.setInt(gamesStartedKey, startedBefore + 1);
    if (shouldShowInterstitial(
      unlocked: PurchaseStore.instance.isUnlocked,
      gamesStartedBefore: startedBefore,
    )) {
      await AdService.instance.showIfReady();
    }
    await widget.controller.startNewGame(
      seed: DateTime.now().millisecondsSinceEpoch,
      players: players,
    );
    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen(controller: widget.controller),
      ),
    );
  }

  static const _bgPath = 'assets/images/ui/bg_menu.png';

  @override
  Widget build(BuildContext context) {
    final hasArt = ArtStore.instance.has(_bgPath);
    return Scaffold(
      backgroundColor: const Color(0xFF2E4034),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Heavier scrim than the menu's: the parchment card and its chips
          // need the valley art pushed further back to read cleanly.
          if (hasArt) ...[
            Positioned.fill(
              child: Image.asset(_bgPath, fit: BoxFit.cover),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.60),
                      Colors.black.withValues(alpha: 0.40),
                    ],
                  ),
                ),
              ),
            ),
          ],
          SafeArea(
            // Scroll view plus a viewport-tall minimum: the card centers when
            // it fits and scrolls instead of overflowing when it does not.
            // (Center alone cannot: a scroll view hands its child unbounded
            // height.)
            // The top inset keeps it clear of the transparent AppBar's chevron.
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, kToolbarHeight, 20, 24),
                    child: Center(child: _card()),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Container(
        decoration: parchmentPanel(radius: 16),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'New Game',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4A3826),
              ),
            ),
            const SizedBox(height: 20),
            _sectionLabel('RIVALS'),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final count in [1, 2, 3])
                  _chip(
                    label: count == 1 ? '1 bot' : '$count bots',
                    selected: _botCount == count,
                    locked: !setupChoiceAllowed(
                      unlocked: PurchaseStore.instance.isUnlocked,
                      botCount: count,
                      difficulty: BotDifficulty.easy,
                    ),
                    onSelected: () => setState(() => _botCount = count),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionLabel('DIFFICULTY'),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in const {
                  BotDifficulty.easy: 'Easy',
                  BotDifficulty.medium: 'Fair',
                  BotDifficulty.hard: 'Cruel',
                }.entries)
                  _chip(
                    label: entry.value,
                    selected: _difficulty == entry.key,
                    locked: !setupChoiceAllowed(
                      unlocked: PurchaseStore.instance.isUnlocked,
                      botCount: 1,
                      difficulty: entry.key,
                    ),
                    onSelected: () => setState(() => _difficulty = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'High-score bonus ×${difficultyMultiplier([
                for (var i = 0; i < _botCount; i++)
                  PlayerState(
                      id: i,
                      name: '',
                      isBot: true,
                      difficulty: _difficulty),
              ])}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9A6B1F),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _start,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              ),
              child: const Text('Begin', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: Color(0xFF7A6647),
        ),
      );

  Widget _chip({
    required String label,
    required bool selected,
    required bool locked,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) {
        SoundStore.instance.playSfx(Sfx.uiTap);
        if (locked) {
          showPaywall(context);
          return;
        }
        onSelected();
      },
      showCheckmark: false,
      selectedColor: const Color(0xFF9A6B1F),
      backgroundColor: const Color(0xFFE7D9B8),
      side: const BorderSide(color: Color(0xFF8A6F4D)),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked) ...[
            const Icon(Icons.lock, size: 14, color: Color(0xFF8A6F4D)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: selected
                  ? Colors.white
                  : locked
                      ? const Color(0xFF8A7B62)
                      : const Color(0xFF3A2E20),
            ),
          ),
        ],
      ),
    );
  }
}
