import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sound effects the game can play. Each has a few recorded variants.
enum Sfx {
  grabJug('grab_jug', 3),
  grabCrimp('grab_crimp', 3),
  grabSloper('grab_sloper', 3),
  foot('foot', 4),
  chalk('chalk', 2),
  slip('slip', 2),
  fall('fall', 1),
  land('land', 2),
  jump('jump', 2),
  catchHold('catch', 2),
  save('save', 1),
  top('top', 1),
  best('best', 1),
  no('no', 1),
  tap('tap', 2),
  bird('bird', 4),
  breath('breath', 2);

  const Sfx(this.file, this.variants);
  final String file;
  final int variants;
}

/// Plays the music, the wind and the sound effects.
///
/// All sounds are files in assets/audio. They were made by the synth in the
/// web prototype (see tool/render_audio.py), so they sound the same.
class GameAudio {
  GameAudio({required bool musicOn, required bool sfxOn, this.enabled = true})
      : _musicOn = musicOn,
        _sfxOn = sfxOn;

  /// Turn off to run without any audio plugin (tests).
  final bool enabled;
  bool _musicOn;
  bool _sfxOn;
  bool get musicOn => _musicOn;
  bool get sfxOn => _sfxOn;

  static const double musicLevel = 0.85;

  /// The wind file was made at this level, so in-game levels are divided by it.
  static const double windFileLevel = 0.25;
  static const int _voices = 8;

  final _rand = math.Random();
  AudioPlayer? _musicPlayer;
  AudioPlayer? _windPlayer;
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  bool _started = false;
  bool _muffled = false;
  bool _suspended = false;
  double _windLevel = 0;
  double _nextBreath = 0;
  double _nextBird = 3;

  Future<void> start() async {
    if (!enabled || _started) return;
    _started = true;
    try {
      AudioCache.instance = AudioCache(prefix: 'assets/audio/');
      final files = <String>['music.mp3', 'wind.mp3'];
      for (final s in Sfx.values) {
        for (var v = 1; v <= s.variants; v++) {
          files.add('${s.file}_$v.mp3');
        }
      }
      // Load in the background; a sound that is not cached yet still plays.
      unawaited(AudioCache.instance.loadAll(files).then((_) {}, onError: (Object _) {}));
      final music = AudioPlayer(playerId: 'music'), wind = AudioPlayer(playerId: 'wind');
      _musicPlayer = music;
      _windPlayer = wind;
      await music.setReleaseMode(ReleaseMode.loop);
      await wind.setReleaseMode(ReleaseMode.loop);
      for (var k = 0; k < _voices; k++) {
        final p = AudioPlayer(playerId: 'sfx$k');
        await p.setReleaseMode(ReleaseMode.stop);
        _pool.add(p);
      }
      await music.play(AssetSource('music.mp3'), volume: _musicOn ? musicLevel : 0);
      await wind.play(AssetSource('wind.mp3'), volume: 0);
    } catch (e) {
      debugPrint('Audio could not start: $e');
    }
  }

  void _safe(Future<void> Function() f) {
    if (!enabled) return;
    f().catchError((Object e) => debugPrint('Audio: $e'));
  }

  void setMusic(bool on) {
    _musicOn = on;
    _applyMusicVolume();
  }

  void setSfx(bool on) {
    _sfxOn = on;
    _applyWindVolume();
  }

  void _applyMusicVolume() {
    final p = _musicPlayer;
    if (p == null) return;
    final v = _musicOn ? (_muffled ? musicLevel * 0.35 : musicLevel) : 0.0;
    _safe(() => p.setVolume(v));
  }

  void _applyWindVolume() {
    final p = _windPlayer;
    if (p == null) return;
    final v = _sfxOn ? (_windLevel / windFileLevel).clamp(0.0, 1.0) : 0.0;
    _safe(() => p.setVolume(v));
  }

  /// Quieter music while the game is paused.
  void muffle(bool on) {
    if (_muffled == on) return;
    _muffled = on;
    _applyMusicVolume();
  }

  /// Wind gets louder as you climb. [level] is 0 to about 0.12.
  void setWind(double level) {
    if (!_started || (level - _windLevel).abs() < 0.004) return;
    _windLevel = level;
    _applyWindVolume();
  }

  /// Stop all sound while the app is in the background.
  void suspend() {
    if (_suspended) return;
    _suspended = true;
    final m = _musicPlayer, w = _windPlayer;
    _safe(() async {
      await m?.pause();
      await w?.pause();
    });
  }

  void resume() {
    if (!_suspended) return;
    _suspended = false;
    final m = _musicPlayer, w = _windPlayer;
    _safe(() async {
      await m?.resume();
      await w?.resume();
    });
  }

  /// Play a sound. [pan] is -1 (left) to 1 (right). [volume] scales it.
  void play(Sfx s, {double pan = 0, double volume = 1}) {
    if (!enabled || !_started || !_sfxOn || _pool.isEmpty) return;
    final v = 1 + _rand.nextInt(s.variants);
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    _safe(() async {
      await p.stop();
      try {
        await p.setBalance(pan.clamp(-1.0, 1.0));
      } catch (_) {
        // Not every platform can pan a sound. That is fine.
      }
      await p.play(AssetSource('${s.file}_$v.mp3'), volume: volume.clamp(0.0, 1.0));
    });
  }

  /// Breathing when a hand is very tired. [level] is 0 to 1.
  void breath(double level, double now) {
    if (now < _nextBreath) return;
    _nextBreath = now + 1.5 - level * 0.5;
    play(Sfx.breath, volume: (0.025 + level * 0.04) / 0.065);
  }

  /// Birds now and then, when [low] (near the ground or on the title screen).
  void ambience(double now, {required bool low}) {
    if (now < _nextBird) return;
    _nextBird = now + 6 + _rand.nextDouble() * 9;
    if (low) play(Sfx.bird, pan: (_rand.nextDouble() - 0.5) * 1.4);
  }

  /// A small buzz on phones.
  void buzz(Sfx s) {
    if (!enabled || kIsWeb) return;
    switch (s) {
      case Sfx.grabJug:
      case Sfx.grabCrimp:
      case Sfx.grabSloper:
        HapticFeedback.selectionClick();
      case Sfx.slip:
      case Sfx.catchHold:
        HapticFeedback.mediumImpact();
      case Sfx.land:
        HapticFeedback.heavyImpact();
      case Sfx.no:
        HapticFeedback.lightImpact();
      default:
        break;
    }
  }
}
