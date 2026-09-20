import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/audio/sound_store.dart';
import 'package:hexstead/screens/game_screen.dart';
import 'package:hexstead/screens/menu_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead/tutorial/tutorial_director.dart';
import 'package:hexstead/widgets/tutorial_banner.dart';
import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InMemorySaveStore implements SaveStore {
  String? saved;

  @override
  Future<void> save(String json) async => saved = json;

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> clear() async => saved = null;
}

String midGameSave() => jsonEncode(gameStateToJson(GameState.newGame(
      seed: 7,
      players: const [
        PlayerSetup(name: 'You', isBot: false),
        PlayerSetup(name: 'Bot', isBot: true),
      ],
    )));

Future<(GameController, InMemorySaveStore)> pumpMenu(
    WidgetTester tester) async {
  final store = InMemorySaveStore()..saved = midGameSave();
  final controller =
      GameController(saveStore: store, botStepDelay: Duration.zero);
  await tester.pumpWidget(
    MaterialApp(home: MenuScreen(controller: controller)),
  );
  await tester.pumpAndSettle();
  return (controller, store);
}

void main() {
  testWidgets('first run offers the tutorial, and only ever once',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpMenu(tester);

    expect(find.text('New to Hexstead?'), findsOneWidget);
    await tester.tap(find.text('Maybe later'));
    await tester.pumpAndSettle();
    expect(find.text('New to Hexstead?'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(tutorialPromptSeenKey), isTrue);

    // A second visit keeps quiet. Tear the tree down first, or the element
    // is reused and initState never runs again - which would prove nothing.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    await pumpMenu(tester);
    expect(find.text('New to Hexstead?'), findsNothing);
    expect(find.text('Tutorial'), findsOneWidget);
  });

  testWidgets('taking the offer launches the guided game', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final (_, store) = await pumpMenu(tester);
    final before = store.saved;

    expect(find.text('New to Hexstead?'), findsOneWidget);
    await tester.tap(find.text('Start tutorial'));
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byType(TutorialBanner), findsOneWidget);
    expect(find.textContaining('Nineteen hexes'), findsOneWidget);

    // The tutorial runs on its own controller and a store that forgets: the
    // autosave behind Continue is exactly as it was.
    expect(store.saved, before);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(tutorialPromptSeenKey), isTrue);
  });

  testWidgets('the Tutorial button is always there, prompt or not',
      (tester) async {
    SharedPreferences.setMockInitialValues({tutorialPromptSeenKey: true});
    final (_, store) = await pumpMenu(tester);
    final before = store.saved;

    expect(find.text('New to Hexstead?'), findsNothing);
    expect(find.text('Tutorial'), findsOneWidget);

    await tester.tap(find.text('Tutorial'));
    await tester.pumpAndSettle();
    expect(find.byType(TutorialBanner), findsOneWidget);
    expect(store.saved, before);
  });

  testWidgets('the sound toggles flip the store and persist', (tester) async {
    SharedPreferences.setMockInitialValues({tutorialPromptSeenKey: true});
    final sound = SoundStore.instance;
    await sound.load();
    await sound.setMusicEnabled(true);
    await sound.setSfxEnabled(true);

    await pumpMenu(tester);
    expect(find.byIcon(Icons.music_note), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    await tester.tap(find.byIcon(Icons.music_note));
    await tester.pumpAndSettle();
    expect(sound.musicEnabled, isFalse);
    expect(find.byIcon(Icons.music_off), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pumpAndSettle();
    expect(sound.sfxEnabled, isFalse);
    expect(find.byIcon(Icons.volume_off), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SoundStore.musicPrefKey), isFalse);
    expect(prefs.getBool(SoundStore.sfxPrefKey), isFalse);

    // And back on again, through the same icons.
    await tester.tap(find.byIcon(Icons.music_off));
    await tester.tap(find.byIcon(Icons.volume_off));
    await tester.pumpAndSettle();
    expect(sound.musicEnabled, isTrue);
    expect(sound.sfxEnabled, isTrue);
    expect(prefs.getBool(SoundStore.musicPrefKey), isTrue);
    expect(prefs.getBool(SoundStore.sfxPrefKey), isTrue);

    // Restore the singleton: it outlives this test.
    await sound.setMusicEnabled(true);
    await sound.setSfxEnabled(true);
  });
}
