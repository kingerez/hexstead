import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'art/art_store.dart';
import 'audio/sound_store.dart';
import 'monetization/purchase_store.dart';
import 'observability/analytics.dart';
import 'screens/menu_screen.dart';
import 'state/game_controller.dart';
import 'state/persistence.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Analytics.instance.init();
  // Crash reporting on top of the framework's own handling: presentError
  // keeps the red screen and the console dump exactly as they were.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Analytics.instance.reportError(details.exception, details.stack);
  };
  // Errors that escape the framework entirely (async gaps, platform
  // callbacks). Claiming one is handled silences the engine's own log, so
  // only claim it when the report actually went somewhere: with analytics
  // off (debug, tests, a failed setup) the console stays the one witness.
  PlatformDispatcher.instance.onError = (error, stack) {
    Analytics.instance.reportError(error, stack);
    return Analytics.instance.active;
  };
  // The whole UI is designed portrait-first; landscape is never a good fit.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await ArtStore.instance.load();
  await SoundStore.instance.load();
  await PurchaseStore.instance.load();
  runApp(
    HexsteadApp(controller: GameController(saveStore: createSaveStore())),
  );
}

/// Route lifecycle feed for screens that must refresh when they come back
/// into view. The menu needs it: a pushReplacement further down the stack
/// (setup -> game) completes its awaited push early, so the push future says
/// nothing about when the user is actually looking at the menu again.
final routeObserver = RouteObserver<PageRoute<dynamic>>();

class HexsteadApp extends StatelessWidget {
  final GameController controller;

  const HexsteadApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hexstead',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B8F4E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // Phone-shaped frame: on wide screens (desktop web) the game runs in
      // a centered portrait "device" with phone dimensions; on real phones
      // it fills the screen as usual.
      builder: (context, child) => _PhoneFrame(child: child!),
      home: MenuScreen(controller: controller),
    );
  }
}

/// Desktop-web affordance: on windows wider than a phone, letterboxes the
/// app into a centered portrait frame with real phone proportions
/// (iPhone-ish 9:19.5), rounded corners, and a bezel. MediaQuery is
/// overridden to the frame size so all in-app layout math sees phone
/// dimensions. Mobile devices - phones AND tablets - always render full
/// screen; the frame never applies there.
class _PhoneFrame extends StatelessWidget {
  final Widget child;

  const _PhoneFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    // Tablets are wider than 520px but are real touch devices, not a
    // desktop browser window - they get the full screen.
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      return child;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 520) return child;
        const aspect = 9 / 19.5;
        final height =
            math.min(constraints.maxHeight - 32, 900.0);
        final width = math.min(430.0, height * aspect);
        final frameHeight = width / aspect;
        return ColoredBox(
          color: const Color(0xFF141A16),
          child: Center(
            child: Container(
              width: width,
              height: frameHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: const Color(0xFF3A463C), width: 6),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 40),
                ],
              ),
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(size: Size(width, frameHeight)),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
