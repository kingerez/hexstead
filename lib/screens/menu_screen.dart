import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../art/art_store.dart';
import '../audio/sound_store.dart';
import '../main.dart';
import '../state/game_controller.dart';
import '../state/persistence.dart';
import '../tutorial/tutorial_director.dart';
import '../tutorial/tutorial_scenario.dart';
import 'game_screen.dart';
import 'setup_screen.dart';

class MenuScreen extends StatefulWidget {
  final GameController controller;

  const MenuScreen({super.key, required this.controller});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with RouteAware {
  // Held in a field rather than started inside build: popping back to the
  // menu does not rebuild its element tree, so the check has to be re-run
  // explicitly whenever the menu becomes visible again - otherwise a game
  // that ended (and cleared the autosave) leaves a dead Continue behind.
  late Future<bool> _resumable;

  /// Mirrors of the store's toggles, so the icons repaint on tap. The store
  /// owns both the live state and the stored prefs.
  bool _music = SoundStore.instance.musicEnabled;
  bool _sfx = SoundStore.instance.sfxEnabled;

  @override
  void initState() {
    super.initState();
    _resumable = widget.controller.hasResumableGame();
    SoundStore.instance.load().then((_) {
      if (!mounted) return;
      setState(() {
        _music = SoundStore.instance.musicEnabled;
        _sfx = SoundStore.instance.sfxEnabled;
      });
    });
    _maybeOfferTutorial();
  }

  /// First run only: offer the guided game once, and remember that the offer
  /// was made whichever way it is answered.
  Future<void> _maybeOfferTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(tutorialPromptSeenKey) == true) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final take = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('New to Hexstead?'),
          content: const Text(
              'Learn the ropes in a short guided game - dice, land, cards '
              'and the bandit, in a few minutes.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Maybe later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Start tutorial'),
            ),
          ],
        ),
      );
      await prefs.setBool(tutorialPromptSeenKey, true);
      if (take == true && mounted) await _startTutorial();
    });
  }

  /// Runs the guided game on a controller of its own, backed by a store that
  /// forgets: the real autosave behind Continue is never touched.
  Future<void> _startTutorial() async {
    _menuTap();
    final navigator = Navigator.of(context);
    final scenario = TutorialScenario();
    final tutorialController = GameController(
      saveStore: NullSaveStore(),
      botBrainOverride: scenario.nextBotAction,
    );
    await tutorialController.startFromState(scenario.initialState());
    if (!mounted) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          controller: tutorialController,
          tutorial: TutorialDirector(),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// Back on screen after a game (or a setup screen backed out of): whatever
  /// happened in there, the Continue button has to be re-decided.
  @override
  void didPopNext() => _refreshResumable();

  void _refreshResumable() {
    if (!mounted) return;
    // Block body, not an arrow: setState rejects a callback that returns a
    // value, and the assignment's value here is a Future.
    setState(() {
      _resumable = widget.controller.hasResumableGame();
    });
  }

  /// Browsers refuse to start audio before a user gesture, so the menu theme
  /// rides the first button tap rather than the first build. The trips back to
  /// the menu restart it from their own side (game over screen, quit to menu).
  void _menuTap() {
    SoundStore.instance.playSfx(Sfx.uiTap);
    SoundStore.instance.startMusic(MusicTrack.menu);
  }

  // Neither push is awaited for a refresh any more: didPopNext is what tells
  // the menu it is back on screen.
  void _newGame() {
    _menuTap();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SetupScreen(controller: widget.controller),
      ),
    );
  }

  Future<void> _continue() async {
    _menuTap();
    final navigator = Navigator.of(context);
    final ok = await widget.controller.resume();
    if (!ok) {
      // The save died under us; hide the button instead of doing nothing.
      _refreshResumable();
      return;
    }
    await navigator.push(
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The valley illustration is light gold; the scrim keeps the white
          // title and white54 tagline readable on top of it.
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
                      Colors.black.withValues(alpha: 0.50),
                      Colors.black.withValues(alpha: 0.30),
                    ],
                  ),
                ),
              ),
            ),
          ],
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('⬡',
                      style: TextStyle(fontSize: 64, color: Colors.amber)),
                  const Text(
                    'Hexstead',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Text(
                    'Claim the realm before the seasons turn',
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 48),
                  FilledButton(
                    onPressed: _newGame,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 48, vertical: 16),
                    ),
                    child:
                        const Text('New Game', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<bool>(
                    future: _resumable,
                    builder: (context, snapshot) => snapshot.data == true
                        ? TextButton(
                            onPressed: _continue,
                            child: const Text('Continue'),
                          )
                        : const SizedBox.shrink(),
                  ),
                  TextButton(
                    onPressed: _startTutorial,
                    child: const Text('Tutorial'),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _soundToggle(
                      on: _music,
                      onIcon: Icons.music_note,
                      offIcon: Icons.music_off,
                      onTap: () {
                        final next = !_music;
                        setState(() => _music = next);
                        SoundStore.instance.setMusicEnabled(next);
                        // Browsers only start audio off a gesture, so this
                        // tap is the menu theme's chance to begin.
                        if (next) {
                          SoundStore.instance.startMusic(MusicTrack.menu);
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    _soundToggle(
                      on: _sfx,
                      onIcon: Icons.volume_up,
                      offIcon: Icons.volume_off,
                      onTap: () {
                        final next = !_sfx;
                        setState(() => _sfx = next);
                        SoundStore.instance.setSfxEnabled(next);
                        if (next) SoundStore.instance.playSfx(Sfx.uiTap);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One circular chrome toggle, styled like the in-game pair.
  Widget _soundToggle({
    required bool on,
    required IconData onIcon,
    required IconData offIcon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on
              ? Colors.amber.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(
          on ? onIcon : offIcon,
          size: 19,
          color: on ? Colors.amber : Colors.white38,
        ),
      ),
    );
  }
}
