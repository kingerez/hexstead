import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/monetization/purchase_gateway.dart';
import 'package:hexstead/monetization/purchase_store.dart';
import 'package:hexstead/screens/setup_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead/widgets/paywall_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeGateway implements PurchaseGateway {
  final events_ = StreamController<PurchaseEvent>.broadcast();

  @override
  bool get supported => true;

  @override
  Stream<PurchaseEvent> get events => events_.stream;

  @override
  Future<String?> queryPrice(String productId) async => r'$3.99';

  @override
  Future<bool> buy(String productId) async => true;

  @override
  Future<void> restore() async {}
}

Future<FakeGateway> pumpSetup(WidgetTester tester,
    {bool unlocked = false}) async {
  SharedPreferences.setMockInitialValues(
      {if (unlocked) 'unlocked_v1': true});
  final gateway = FakeGateway();
  PurchaseStore.instance =
      PurchaseStore(gateway, restoreSettle: Duration.zero);
  await PurchaseStore.instance.load();
  await tester.pumpWidget(MaterialApp(
    home: SetupScreen(controller: GameController(saveStore: NullSaveStore())),
  ));
  await tester.pump();
  return gateway;
}

void main() {
  testWidgets('free tier defaults to 1 bot on Easy', (tester) async {
    await pumpSetup(tester);
    final oneBot = tester.widget<ChoiceChip>(find.ancestor(
        of: find.text('1 bot'), matching: find.byType(ChoiceChip)));
    final easy = tester.widget<ChoiceChip>(find.ancestor(
        of: find.text('Easy'), matching: find.byType(ChoiceChip)));
    expect(oneBot.selected, isTrue);
    expect(easy.selected, isTrue);
  });

  testWidgets('locked chips open the paywall instead of selecting',
      (tester) async {
    await pumpSetup(tester);
    await tester.tap(find.text('2 bots'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallDialog), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // dismiss barrier
    await tester.pumpAndSettle();
    final twoBots = tester.widget<ChoiceChip>(find.ancestor(
        of: find.text('2 bots'), matching: find.byType(ChoiceChip)));
    expect(twoBots.selected, isFalse);
  });

  testWidgets('locked chips carry a lock icon', (tester) async {
    await pumpSetup(tester);
    // 2 bots, 3 bots, Fair, Cruel are locked in the free tier.
    expect(find.byIcon(Icons.lock), findsNWidgets(4));
  });

  testWidgets('unlocked players select anything, no locks, no paywall',
      (tester) async {
    await pumpSetup(tester, unlocked: true);
    expect(find.byIcon(Icons.lock), findsNothing);
    await tester.tap(find.text('Cruel'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallDialog), findsNothing);
    final cruel = tester.widget<ChoiceChip>(find.ancestor(
        of: find.text('Cruel'), matching: find.byType(ChoiceChip)));
    expect(cruel.selected, isTrue);
  });

  testWidgets('chips unlock live when the purchase lands', (tester) async {
    final gateway = await pumpSetup(tester);
    gateway.events_.add(const PurchaseEvent(PurchaseEventType.purchased));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock), findsNothing);
  });
}
