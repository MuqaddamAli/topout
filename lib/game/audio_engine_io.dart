import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_engine.dart';

AudioEngine createEngine() => _PlayersEngine();

/// Phones and desktops: audioplayers, with a pool of low-latency players for
/// the effects (SoundPool on Android).
class _PlayersEngine implements AudioEngine {
  static const int _voices = 8;

  final _music = AudioPlayer(playerId: 'music');
  final _wind = AudioPlayer(playerId: 'wind');
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  double _musicVolume = 0;
  bool _suspended = false;

  void _safe(Future<void> Function() f) {
    f().catchError((Object e) => debugPrint('Audio: $e'));
  }

  @override
  Future<void> start(List<String> effects, {required double music}) async {
    AudioCache.instance = AudioCache(prefix: 'assets/audio/');
    // Load in the background; a sound that is not cached yet still plays.
    unawaited(AudioCache.instance.loadAll([for (final e in effects) '$e.mp3']).then((_) {}, onError: (Object _) {}));
    await _music.setReleaseMode(ReleaseMode.loop);
    await _wind.setReleaseMode(ReleaseMode.loop);
    for (var k = 0; k < _voices; k++) {
      final p = AudioPlayer(playerId: 'sfx$k');
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setReleaseMode(ReleaseMode.stop);
      _pool.add(p);
    }
    await _wind.play(AssetSource('wind.mp3'), volume: 0);
    setMusic(music, muffled: false);
  }

  @override
  void play(String effect, {required double volume, required double pan}) {
    if (_pool.isEmpty || _suspended) return;
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    _safe(() async {
      await p.stop();
      try {
        await p.setBalance(pan);
      } catch (_) {
        // Not every platform can pan a sound. That is fine.
      }
      await p.play(AssetSource('$effect.mp3'), volume: volume);
    });
  }

  @override
  void setMusic(double volume, {required bool muffled}) {
    _musicVolume = muffled ? volume * 0.35 : volume;
    _applyMusic();
  }

  void _applyMusic() {
    final v = _musicVolume;
    _safe(() async {
      if (v == 0 || _suspended) {
        if (_music.state == PlayerState.playing) await _music.pause();
        return;
      }
      await _music.setVolume(v);
      if (_music.source == null) {
        await _music.play(AssetSource('music.mp3'), volume: v);
      } else if (_music.state != PlayerState.playing) {
        await _music.resume();
      }
    });
  }

  @override
  void setWind(double volume) => _safe(() => _wind.setVolume(volume));

  @override
  void suspend() {
    if (_suspended) return;
    _suspended = true;
    _applyMusic();
    _safe(_wind.pause);
  }

  @override
  void resume() {
    if (!_suspended) return;
    _suspended = false;
    _applyMusic();
    _safe(_wind.resume);
  }
}
