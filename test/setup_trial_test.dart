import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/monetization/ad_service.dart';
import 'package:hexstead/monetization/entitlements.dart';
import 'package:hexstead/monetization/purchase_gateway.dart';
import 'package:hexstead/monetization/purchase_store.dart';
import 'package:hexstead/screens/setup_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingAdService implements AdService {
  int preloads = 0;
  int shows = 0;

  @override
  void preload() => preloads++;

  @override
  Future<void> showIfReady() async => shows++;
}

class Harness {
  final GameController controller;
  final RecordingAdService ads;

  Harness(this.controller, this.ads);
}

Future<Harness> pumpSetup(
  WidgetTester tester, {
  bool unlocked = false,
  bool trialUsed = false,
  int gamesStarted = 0,
}) async {
  SharedPreferences.setMockInitialValues({
    if (unlocked) unlockedCacheKey: true,
    if (trialUsed) trialUsedKey: true,
    gamesStartedKey: gamesStarted,
  });
  PurchaseStore.instance =
      PurchaseStore(UnsupportedPurchaseGateway(), restoreSettle: Duration.zero);
  await PurchaseStore.instance.load();
  final ads = RecordingAdService();
  AdService.instance = ads;
  final controller = GameController(saveStore: NullSaveStore());
  await tester.pumpWidget(MaterialApp(
    home: SetupScreen(controller: controller),
  ));
  await tester.pumpAndSettle();
  return Harness(controller, ads);
}

void main() {
  testWidgets('locked players are offered the tasting, chips stay locked',
      (tester) async {
    await pumpSetup(tester);
    expect(find.text('Try it'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNWidgets(4));
  });

  testWidgets('a spent tasting is not offered again', (tester) async {
    await pumpSetup(tester, trialUsed: true);
    expect(find.text('Try it'), findsNothing);
    expect(find.text('FREE TASTING'), findsNothing);
  });

  testWidgets('unlocked players are never offered the tasting',
      (tester) async {
    await pumpSetup(tester, unlocked: true);
    expect(find.text('Try it'), findsNothing);
  });

  testWidgets('the tasting starts two Fair bots, spends itself, no ad',
      (tester) async {
    final harness = await pumpSetup(tester, gamesStarted: 3);
    // The card outgrows the 800x600 test viewport and scrolls.
    await tester.ensureVisible(find.text('Try it'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try it'));
    // startNewGame runs a real board setup; give it generous settle time.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final bots =
        harness.controller.state!.players.where((p) => p.isBot).toList();
    expect(bots.length, 2);
    expect(bots.every((p) => p.difficulty == BotDifficulty.medium), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(trialUsedKey), isTrue);
    expect(prefs.getInt(gamesStartedKey), 4);
    expect(harness.ads.shows, 0);
  });
}
