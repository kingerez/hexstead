import 'package:flutter/material.dart';

import 'screens/menu_screen.dart';
import 'state/game_controller.dart';
import 'state/persistence.dart';

void main() {
  runApp(
    HexsteadApp(controller: GameController(saveStore: createSaveStore())),
  );
}

class HexsteadApp extends StatelessWidget {
  final GameController controller;

  const HexsteadApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hexstead',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B8F4E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // Phone-shaped frame: on wide screens (desktop web) the game stays a
      // centered portrait column instead of stretching across the monitor.
      builder: (context, child) => ColoredBox(
        color: const Color(0xFF1B231D),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: child!,
          ),
        ),
      ),
      home: MenuScreen(controller: controller),
    );
  }
}
