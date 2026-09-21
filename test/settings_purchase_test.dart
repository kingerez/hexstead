import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/monetization/entitlements.dart';
import 'package:hexstead/monetization/purchase_gateway.dart';
import 'package:hexstead/monetization/purchase_store.dart';
import 'package:hexstead/widgets/paywall_dialog.dart';
import 'package:hexstead/widgets/settings_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeGateway implements PurchaseGateway {
  FakeGateway({this.isSupported = true, this.restoreUnlocks = false});

  final bool isSupported;
  final bool restoreUnlocks;
  final events_ = StreamController<PurchaseEvent>.broadcast();

  @override
  bool get supported => isSupported;

  @override
  Stream<PurchaseEvent> get events => events_.stream;

  @override
  Future<String?> queryPrice(String productId) async => r'$3.99';

  @override
  Future<bool> buy(String productId) async => true;

  @override
  Future<void> restore() async {
    if (restoreUnlocks) {
      events_.add(const PurchaseEvent(PurchaseEventType.restored));
    }
  }
}

Future<void> pumpSettings(WidgetTester tester, FakeGateway gateway,
    {bool unlocked = false}) async {
  SharedPreferences.setMockInitialValues(
      {if (unlocked) unlockedCacheKey: true});
  PurchaseStore.instance =
      PurchaseStore(gateway, restoreSettle: Duration.zero);
  await PurchaseStore.instance.load();
  await tester.pumpWidget(MaterialApp(
    home: Stack(children: [
      SettingsOverlay(onClose: () {}, onQuitToMenu: () {}),
    ]),
  ));
  await tester.pump();
}

void main() {
  testWidgets('locked players see unlock and restore entries',
      (tester) async {
    await pumpSettings(tester, FakeGateway());
    expect(find.text('Unlock full game'), findsOneWidget);
    expect(find.text('Restore purchases'), findsOneWidget);
  });

  testWidgets('unlock entry opens the paywall', (tester) async {
    await pumpSettings(tester, FakeGateway());
    await tester.tap(find.text('Unlock full game'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallDialog), findsOneWidget);
  });

  testWidgets('restore with a past purchase reports success',
      (tester) async {
    await pumpSettings(tester, FakeGateway(restoreUnlocks: true));
    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase restored - enjoy!'), findsOneWidget);
  });

  testWidgets('restore with nothing to restore says so', (tester) async {
    await pumpSettings(tester, FakeGateway());
    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    expect(find.text('No purchase found for this account'), findsOneWidget);
  });

  testWidgets('unlocked players see neither entry', (tester) async {
    await pumpSettings(tester, FakeGateway(), unlocked: true);
    expect(find.text('Unlock full game'), findsNothing);
    expect(find.text('Restore purchases'), findsNothing);
  });

  testWidgets('web (unsupported store) shows neither entry', (tester) async {
    await pumpSettings(tester, FakeGateway(isSupported: false));
    expect(find.text('Unlock full game'), findsNothing);
    expect(find.text('Restore purchases'), findsNothing);
  });
}
