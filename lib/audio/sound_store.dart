import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two looping background tracks.
enum MusicTrack {
  menu('music_menu'),
  game('music_game');

  const MusicTrack(this.file);

  /// Base name under assets/audio/, extension excluded.
  final String file;
}

/// Every one-shot the game can fire.
enum Sfx {
  diceRoll('sfx_dice_roll'),
  cardPlay('sfx_card_play'),
  claim('sfx_claim'),
  upgrade('sfx_upgrade'),
  production('sfx_production'),
  bandit('sfx_bandit'),
  matchPoint('sfx_match_point'),
  victory('sfx_victory'),
  defeat('sfx_defeat');

  const Sfx(this.file);

  /// Base name under assets/audio/, extension excluded.
  final String file;
}

/// Central audio registry with per-asset fallback, mirroring ArtStore: any
/// m4a present under assets/audio/ plays, anything missing is a silent no-op.
/// Load once at startup; callers fire and forget afterwards.
///
/// Nothing here ever throws: the plugin is absent in widget tests and the
/// files may not be bundled yet, so a failure switches audio off for the rest
/// of the session instead of surfacing.
class SoundStore {
  static final SoundStore instance = SoundStore._();

  SoundStore._();

  /// Pref keys shared with the settings overlay - this store owns the writes.
  static const musicPrefKey = 'music_on';
  static const sfxPrefKey = 'sounds_on';

  static const _dir = 'assets/audio/';

  /// Music sits under the ceremony sounds rather than competing with them.
  static const _musicVolume = 0.35;
  static const _sfxVolume = 0.9;

  final Set<String> _available = {};

  /// One pre-sourced player per effect: reuse keeps the latency down, and
  /// restarting a still-playing effect is what a UI one-shot wants anyway.
  /// (AudioPool is not used: its low-latency players are never handed back to
  /// the pool, so it would grow without bound.)
  final Map<Sfx, AudioPlayer> _sfxPlayers = {};

  AudioPlayer? _musicPlayer;

  /// Track the game wants (it outlives the music toggle going off) and the one
  /// actually playing.
  MusicTrack? _wanted;
  MusicTrack? _playing;

  bool _loaded = false;
  bool _musicOn = true;
  bool _sfxOn = true;

  /// Set once the platform side has failed: no plugin, no audio session. Every
  /// later call returns immediately instead of retrying per sound.
  bool _broken = false;

  bool get musicEnabled => _musicOn;
  bool get sfxEnabled => _sfxOn;

  /// Discovers which audio files were bundled and reads the two toggles.
  /// Safe to call more than once; only the first call does the work.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _available
          .addAll(manifest.listAssets().where((a) => a.startsWith(_dir)));
    } catch (_) {
      // No assets bundled yet - the game stays silent.
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _musicOn = prefs.getBool(musicPrefKey) ?? true;
      _sfxOn = prefs.getBool(sfxPrefKey) ?? true;
    } catch (_) {
      // Prefs unavailable (no plugin) - the defaults stand.
    }
  }

  bool _has(String file) => _available.contains('$_dir$file.m4a');

  /// AssetSource resolves against AudioCache's 'assets/' prefix.
  Source _source(String file) => AssetSource('audio/$file.m4a');

  /// Fires a one-shot. No-op when sounds are off or the file is not bundled.
  Future<void> playSfx(Sfx sfx) async {
    if (!_sfxOn || _broken || !_has(sfx.file)) return;
    try {
      var player = _sfxPlayers[sfx];
      if (player == null) {
        player = AudioPlayer();
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(_source(sfx.file));
        await player.setVolume(_sfxVolume);
        _sfxPlayers[sfx] = player;
      } else {
        await player.stop();
      }
      await player.resume();
    } catch (_) {
      _broken = true;
    }
  }

  /// Loops [track] as the background music, replacing whatever was playing.
  Future<void> startMusic(MusicTrack track) async {
    _wanted = track;
    await _syncMusic();
  }

  Future<void> stopMusic() async {
    _wanted = null;
    await _syncMusic();
  }

  Future<void> setMusicEnabled(bool on) async {
    if (_musicOn == on) return;
    _musicOn = on;
    await _persist(musicPrefKey, on);
    await _syncMusic();
  }

  Future<void> setSfxEnabled(bool on) async {
    if (_sfxOn == on) return;
    _sfxOn = on;
    await _persist(sfxPrefKey, on);
  }

  /// Brings the player in line with [_wanted] and the music toggle.
  Future<void> _syncMusic() async {
    if (_broken) return;
    var target = _musicOn ? _wanted : null;
    // Only half the music can be bundled: a screen whose track is missing
    // falls silent rather than keeping the previous screen's loop running.
    if (target != null && !_has(target.file)) target = null;
    if (target == _playing) return;
    if (target == null) {
      _playing = null;
      try {
        await _musicPlayer?.stop();
      } catch (_) {
        _broken = true;
      }
      return;
    }
    _playing = target;
    try {
      final player = _musicPlayer ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(_source(target.file), volume: _musicVolume);
    } catch (_) {
      _playing = null;
      _broken = true;
    }
  }

  Future<void> _persist(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Prefs unavailable - the toggle still applies for this session.
    }
  }
}
