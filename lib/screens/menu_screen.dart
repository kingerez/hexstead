import 'package:flutter/material.dart';

import '../art/art_store.dart';
import '../state/game_controller.dart';
import 'game_screen.dart';
import 'setup_screen.dart';

class MenuScreen extends StatefulWidget {
  final GameController controller;

  const MenuScreen({super.key, required this.controller});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  // Held in a field rather than started inside build: popping back to the
  // menu does not rebuild its element tree, so the check has to be re-run
  // explicitly whenever the menu becomes visible again - otherwise a game
  // that ended (and cleared the autosave) leaves a dead Continue behind.
  late Future<bool> _resumable;

  @override
  void initState() {
    super.initState();
    _resumable = widget.controller.hasResumableGame();
  }

  void _refreshResumable() {
    if (!mounted) return;
    // Block body, not an arrow: setState rejects a callback that returns a
    // value, and the assignment's value here is a Future.
    setState(() {
      _resumable = widget.controller.hasResumableGame();
    });
  }

  Future<void> _newGame() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SetupScreen(controller: widget.controller),
      ),
    );
    _refreshResumable();
  }

  Future<void> _continue() async {
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
    _refreshResumable();
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
