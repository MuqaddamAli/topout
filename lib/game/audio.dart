import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_engine.dart';

/// Sound effects the game can play. Each has a few variants, and a level
/// that sets it in the mix.
enum Sfx {
  grabJug('grab_jug', 3),
  grabCrimp('grab_crimp', 3),
  grabSloper('grab_sloper', 3),
  foot('foot', 4),
  chalk('chalk', 2, 0.7),
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
  breath('breath', 2),
  snatch('snatch', 2),
  heart('heart', 1);

  const Sfx(this.file, this.variants, [this.level = 1]);
  final String file;
  final int variants;
  final double level;
}

/// Plays the music, the wind and the sound effects.
///
/// All sounds are files in assets/audio, made by tool/make_audio.py. The
/// files are already balanced against each other; the levels here set the
/// music and the wind under the effects.
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

  static const double musicLevel = 0.55;

  /// The game asks for wind from 0 to about 0.12; times this is the volume.
  static const double windScale = 4;

  final _rand = math.Random();
  final _lastVariant = List<int>.filled(Sfx.values.length, 0);
  AudioEngine? _engine;
  bool _muffled = false;
  double _windLevel = 0;
  double _nextBreath = 0;
  double _nextBird = 3;

  /// Starts the sound. On the web this must come from a tap.
  Future<void> start() async {
    if (!enabled || _engine != null) return;
    try {
      final engine = _engine = AudioEngine();
      await engine.start([
        for (final s in Sfx.values)
          for (var v = 1; v <= s.variants; v++) '${s.file}_$v',
      ], music: _musicOn ? musicLevel : 0);
      _applyWind();
    } catch (e) {
      debugPrint('Audio could not start: $e');
    }
  }

  void setMusic(bool on) {
    _musicOn = on;
    _applyMusic();
  }

  void setSfx(bool on) {
    _sfxOn = on;
    _applyWind();
  }

  void _applyMusic() => _engine?.setMusic(_musicOn ? musicLevel : 0, muffled: _muffled);

  void _applyWind() => _engine?.setWind(_sfxOn ? (_windLevel * windScale).clamp(0.0, 1.0) : 0);

  /// Quieter, darker music while the game is paused.
  void muffle(bool on) {
    if (_muffled == on) return;
    _muffled = on;
    _applyMusic();
  }

  /// Wind gets louder as you climb. [level] is 0 to about 0.12.
  void setWind(double level) {
    if ((level - _windLevel).abs() < 0.004) return;
    _windLevel = level;
    _applyWind();
  }

  /// Stop all sound while the app is in the background.
  void suspend() => _engine?.suspend();

  void resume() => _engine?.resume();

  /// Play a sound. [pan] is -1 (left) to 1 (right). [volume] scales it.
  /// The same variant never plays twice in a row.
  void play(Sfx s, {double pan = 0, double volume = 1}) {
    final engine = _engine;
    if (engine == null || !_sfxOn) return;
    var v = 1 + _rand.nextInt(s.variants);
    if (v == _lastVariant[s.index] && s.variants > 1) v = v % s.variants + 1;
    _lastVariant[s.index] = v;
    engine.play('${s.file}_$v', volume: (volume * s.level).clamp(0.0, 1.0), pan: pan.clamp(-1.0, 1.0));
  }

  /// Breathing when a hand is nearly out of grip. [level] is 0 to 1.
  void breath(double level, double now) {
    if (now < _nextBreath) return;
    _nextBreath = now + 2.2 + _rand.nextDouble() * 0.8 - level * 0.4;
    play(Sfx.breath, volume: 0.35 + level * 0.35);
  }

  /// Birds now and then, when [low] (near the ground or on the title screen).
  void ambience(double now, {required bool low}) {
    if (now < _nextBird) return;
    _nextBird = now + 12 + _rand.nextDouble() * 16;
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
      case Sfx.snatch:
        HapticFeedback.heavyImpact();
      case Sfx.no:
        HapticFeedback.lightImpact();
      default:
        break;
    }
  }
}
