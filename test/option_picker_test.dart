import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/board/board_painter.dart';
import 'package:hexstead/widgets/option_picker_dialog.dart';
import 'package:hexstead/widgets/resource_icon.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

/// Pumps a screen whose one button opens the picker, and hands back a
/// reader for whatever the picker eventually answered.
Future<String? Function()> _pumpPicker(
  WidgetTester tester,
  String title,
  List<PickerOption<String>> options,
) async {
  String? answer;
  var answered = false;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              answer = await showOptionPicker<String>(
                context: context,
                title: title,
                options: options,
              );
              answered = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  return () {
    expect(answered, isTrue, reason: 'the picker never returned');
    return answer;
  };
}

void main() {
  testWidgets('the resource picker shows art and capitalized names',
      (tester) async {
    final result = await _pumpPicker(tester, 'Take 2 of…', [
      for (final r in Resource.values)
        PickerOption(
          leading: ResourceIcon(r, size: 22),
          label: r.name[0].toUpperCase() + r.name.substring(1),
          value: r.name,
        ),
    ]);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Take 2 of…'), findsOneWidget);
    expect(find.text('Wood'), findsOneWidget);
    expect(find.text('Grain'), findsOneWidget);
    expect(find.text('Brick'), findsOneWidget);
    expect(find.text('Stone'), findsOneWidget);
    // Every row carries the HUD's own resource mark.
    expect(find.byType(ResourceIcon), findsNWidgets(4));

    await tester.tap(find.text('Brick'));
    await tester.pumpAndSettle();
    expect(find.text('Take 2 of…'), findsNothing);
    expect(result(), 'brick');
  });

  testWidgets('the rival picker shows each player in their board color',
      (tester) async {
    final result = await _pumpPicker(tester, 'Steal from…', [
      for (final (id, name) in const [(1, 'Rosalind'), (2, 'Bertram')])
        PickerOption(
          leading: PlayerSwatch(BoardPainter.playerColors[id]),
          label: name,
          value: name,
        ),
    ]);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerSwatch), findsNWidgets(2));
    final colors = tester
        .widgetList<PlayerSwatch>(find.byType(PlayerSwatch))
        .map((s) => s.color)
        .toList();
    expect(colors, [
      BoardPainter.playerColors[1],
      BoardPainter.playerColors[2],
    ]);

    await tester.tap(find.text('Bertram'));
    await tester.pumpAndSettle();
    expect(result(), 'Bertram');
  });

  testWidgets('tapping outside answers nothing', (tester) async {
    final result = await _pumpPicker(tester, 'Take 2 of…', [
      PickerOption(
        leading: const ResourceIcon(Resource.wood, size: 22),
        label: 'Wood',
        value: 'wood',
      ),
    ]);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Wood'), findsOneWidget);

    // The scrim, well clear of the 280-wide panel.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Take 2 of…'), findsNothing);
    expect(result(), isNull);
  });
}
