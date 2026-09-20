import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/audio/sound_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // No audio files are bundled and the audioplayers plugin has no platform
  // side in a widget test: every call must be a silent no-op rather than a
  // throw, which is what lets the rest of the suite ignore audio entirely.
  test('loads and plays silently with no assets bundled', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SoundStore.instance;

    await store.load();
    expect(store.musicEnabled, isTrue);
    expect(store.sfxEnabled, isTrue);

    for (final sfx in Sfx.values) {
      await store.playSfx(sfx);
    }
    await store.startMusic(MusicTrack.menu);
    await store.startMusic(MusicTrack.game);
    await store.stopMusic();
  });

  test('toggles apply and persist through the shared pref keys', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SoundStore.instance;
    await store.load();

    await store.setMusicEnabled(false);
    await store.setSfxEnabled(false);
    expect(store.musicEnabled, isFalse);
    expect(store.sfxEnabled, isFalse);
    await store.playSfx(Sfx.claim);
    await store.startMusic(MusicTrack.game);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SoundStore.musicPrefKey), isFalse);
    expect(prefs.getBool(SoundStore.sfxPrefKey), isFalse);

    // Restore the singleton: it outlives this test.
    await store.setMusicEnabled(true);
    await store.setSfxEnabled(true);
  });
}
