import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/monetization/purchase_gateway.dart';
import 'package:hexstead/monetization/purchase_store.dart';
import 'package:hexstead/widgets/paywall_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeGateway implements PurchaseGateway {
  FakeGateway({this.isSupported = true});

  final bool isSupported;
  final events_ = StreamController<PurchaseEvent>.broadcast();
  bool buyCalled = false;

  @override
  bool get supported => isSupported;

  @override
  Stream<PurchaseEvent> get events => events_.stream;

  @override
  Future<String?> queryPrice(String productId) async => r'$3.99';

  @override
  Future<bool> buy(String productId) async {
    buyCalled = true;
    return true;
  }

  @override
  Future<void> restore() async {}
}

Future<void> openPaywall(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => showPaywall(context),
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the price and starts a purchase', (tester) async {
    final gateway = FakeGateway();
    PurchaseStore.instance =
        PurchaseStore(gateway, restoreSettle: Duration.zero);
    await PurchaseStore.instance.load();

    await openPaywall(tester);
    expect(find.textContaining(r'$3.99'), findsOneWidget);

    await tester.tap(find.textContaining('Unlock').last);
    await tester.pump();
    expect(gateway.buyCalled, isTrue);
  });

  testWidgets('closes itself when the purchase lands', (tester) async {
    final gateway = FakeGateway();
    PurchaseStore.instance =
        PurchaseStore(gateway, restoreSettle: Duration.zero);
    await PurchaseStore.instance.load();

    await openPaywall(tester);
    gateway.events_.add(const PurchaseEvent(PurchaseEventType.purchased));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallDialog), findsNothing);
  });

  testWidgets('unsupported platform shows the store links card',
      (tester) async {
    PurchaseStore.instance = PurchaseStore(FakeGateway(isSupported: false),
        restoreSettle: Duration.zero);
    await PurchaseStore.instance.load();

    await openPaywall(tester);
    expect(find.text('App Store'), findsOneWidget);
    expect(find.text('Google Play'), findsOneWidget);
  });

  testWidgets('a purchase error is shown in the dialog', (tester) async {
    final gateway = FakeGateway();
    PurchaseStore.instance =
        PurchaseStore(gateway, restoreSettle: Duration.zero);
    await PurchaseStore.instance.load();

    await openPaywall(tester);
    gateway.events_
        .add(const PurchaseEvent(PurchaseEventType.error, 'declined'));
    await tester.pumpAndSettle();
    expect(find.text('declined'), findsOneWidget);
  });
}
