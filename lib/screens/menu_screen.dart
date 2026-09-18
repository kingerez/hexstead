import 'package:flutter/material.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

import '../art/art_store.dart';
import '../state/game_controller.dart';
import 'game_screen.dart';
import 'setup_screen.dart';

class MenuScreen extends StatelessWidget {
  final GameController controller;

  const MenuScreen({super.key, required this.controller});

  Future<void> _continue(BuildContext context) async {
    final navigator = Navigator.of(context);
    final ok = await controller.resume();
    if (!ok) return;
    if (controller.state!.phase == Phase.gameOver) return;
    navigator.push(
      MaterialPageRoute(builder: (_) => GameScreen(controller: controller)),
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
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SetupScreen(controller: controller),
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 48, vertical: 16),
                    ),
                    child:
                        const Text('New Game', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<bool>(
                    future: controller.hasResumableGame(),
                    builder: (context, snapshot) => snapshot.data == true
                        ? TextButton(
                            onPressed: () => _continue(context),
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
