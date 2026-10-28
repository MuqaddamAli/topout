import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'audio_engine.dart';

AudioEngine createEngine() => _WebAudioEngine();

/// Browsers: one AudioContext for everything.
///
/// Effects and the wind are fetched and decoded once, then played from
/// memory, so a grab costs a few audio nodes and no network or element work.
/// The music streams from an `<audio>` element (decoded, the loop would take
/// about 30 MB) through a gain and a low-pass filter for the pause muffle.
class _WebAudioEngine implements AudioEngine {
  final web.AudioContext _ctx = web.AudioContext();
  final Map<String, web.AudioBuffer> _buffers = {};
  web.HTMLAudioElement? _music;
  web.GainNode? _musicGain;
  web.BiquadFilterNode? _musicFilter;
  web.GainNode? _windGain;
  bool _musicOn = false;
  bool _suspended = false;

  static String _url(String name) => ui_web.assetManager.getAssetUrl('assets/audio/$name.mp3');

  @override
  Future<void> start(List<String> effects, {required double music}) async {
    _wake();
    final element = web.HTMLAudioElement()
      ..src = _url('music')
      ..loop = true
      ..preload = 'auto';
    final filter = _ctx.createBiquadFilter()..type = 'lowpass';
    filter.frequency.value = 20000;
    final gain = _ctx.createGain();
    gain.gain.value = music;
    _ctx.createMediaElementSource(element).connect(filter);
    filter.connect(gain);
    gain.connect(_ctx.destination);
    _music = element;
    _musicFilter = filter;
    _musicGain = gain;
    _musicOn = music > 0;
    _syncMusic();

    final wind = _ctx.createGain();
    wind.gain.value = 0;
    wind.connect(_ctx.destination);
    _windGain = wind;
    await Future.wait([
      for (final name in effects) _load(name).then((b) => b == null ? null : _buffers[name] = b),
      _load('wind').then((b) {
        if (b == null) return;
        final loop = _ctx.createBufferSource()
          ..buffer = b
          ..loop = true;
        loop.connect(wind);
        loop.start();
      }),
    ]);
  }

  Future<web.AudioBuffer?> _load(String name) async {
    try {
      final response = await web.window.fetch(_url(name).toJS).toDart;
      if (!response.ok) return null;
      final data = await response.arrayBuffer().toDart;
      return await _ctx.decodeAudioData(data).toDart;
    } catch (e) {
      debugPrint('Audio: could not load $name: $e');
      return null;
    }
  }

  /// A context made before the first tap starts suspended.
  void _wake() {
    if (!_suspended && _ctx.state == 'suspended') unawaited(_ctx.resume().toDart.then((_) {}, onError: (Object _) {}));
  }

  /// Plays the music element when it is on and the app is in front.
  void _syncMusic() {
    final m = _music;
    if (m == null) return;
    if (_musicOn && !_suspended) {
      if (m.paused) unawaited(m.play().toDart.then((_) {}, onError: (Object e) => debugPrint('Audio: music: $e')));
    } else if (!m.paused) {
      m.pause();
    }
  }

  @override
  void play(String effect, {required double volume, required double pan}) {
    final buffer = _buffers[effect];
    if (buffer == null || _suspended) return;
    _wake();
    final source = _ctx.createBufferSource()..buffer = buffer;
    final gain = _ctx.createGain();
    gain.gain.value = volume;
    source.connect(gain);
    if (pan == 0) {
      gain.connect(_ctx.destination);
    } else {
      final panner = _ctx.createStereoPanner();
      panner.pan.value = pan;
      gain.connect(panner);
      panner.connect(_ctx.destination);
    }
    source.start();
  }

  @override
  void setMusic(double volume, {required bool muffled}) {
    final gain = _musicGain, filter = _musicFilter;
    if (gain == null || filter == null) return;
    final now = _ctx.currentTime;
    gain.gain.setTargetAtTime(muffled ? volume * 0.5 : volume, now, 0.12);
    filter.frequency.setTargetAtTime(muffled ? 700 : 20000, now, 0.12);
    _musicOn = volume > 0;
    _syncMusic();
  }

  @override
  void setWind(double volume) => _windGain?.gain.setTargetAtTime(volume, _ctx.currentTime, 0.4);

  @override
  void suspend() {
    if (_suspended) return;
    _suspended = true;
    _syncMusic();
    unawaited(_ctx.suspend().toDart.then((_) {}, onError: (Object _) {}));
  }

  @override
  void resume() {
    if (!_suspended) return;
    _suspended = false;
    unawaited(_ctx.resume().toDart.then((_) {}, onError: (Object _) {}));
    _syncMusic();
  }
}
