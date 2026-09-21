import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/monetization/ad_service.dart';
import 'package:hexstead/monetization/entitlements.dart';
import 'package:hexstead/monetization/purchase_gateway.dart';
import 'package:hexstead/monetization/purchase_store.dart';
import 'package:hexstead/screens/setup_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingAdService implements AdService {
  int preloads = 0;
  int shows = 0;

  @override
  void preload() => preloads++;

  @override
  Future<void> showIfReady() async => shows++;
}

Future<RecordingAdService> pumpAndStart(WidgetTester tester,
    {required bool unlocked, required int gamesStarted}) async {
  SharedPreferences.setMockInitialValues({
    if (unlocked) unlockedCacheKey: true,
    gamesStartedKey: gamesStarted,
  });
  PurchaseStore.instance = PurchaseStore(UnsupportedPurchaseGateway(),
      restoreSettle: Duration.zero);
  await PurchaseStore.instance.load();
  final ads = RecordingAdService();
  AdService.instance = ads;
  await tester.pumpWidget(MaterialApp(
    home: SetupScreen(controller: GameController(saveStore: NullSaveStore())),
  ));
  await tester.pump();
  await tester.tap(find.text('Begin'));
  // startNewGame runs a real board setup; give it generous settle time.
  await tester.pumpAndSettle(const Duration(seconds: 1));
  return ads;
}

void main() {
  testWidgets('second game for a free player shows the interstitial',
      (tester) async {
    final ads =
        await pumpAndStart(tester, unlocked: false, gamesStarted: 1);
    expect(ads.shows, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(gamesStartedKey), 2);
  });

  testWidgets('first game stays clean', (tester) async {
    final ads =
        await pumpAndStart(tester, unlocked: false, gamesStarted: 0);
    expect(ads.shows, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(gamesStartedKey), 1);
  });

  testWidgets('unlocked players never see an ad and never preload',
      (tester) async {
    final ads =
        await pumpAndStart(tester, unlocked: true, gamesStarted: 9);
    expect(ads.shows, 0);
    expect(ads.preloads, 0);
  });

  testWidgets('eligible free players preload on the setup screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({gamesStartedKey: 1});
    PurchaseStore.instance = PurchaseStore(UnsupportedPurchaseGateway(),
        restoreSettle: Duration.zero);
    await PurchaseStore.instance.load();
    final ads = RecordingAdService();
    AdService.instance = ads;
    await tester.pumpWidget(MaterialApp(
      home:
          SetupScreen(controller: GameController(saveStore: NullSaveStore())),
    ));
    await tester.pumpAndSettle();
    expect(ads.preloads, 1);
  });
}
