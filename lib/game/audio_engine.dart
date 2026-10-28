import 'audio_engine_io.dart' if (dart.library.js_interop) 'audio_engine_web.dart' as platform;

/// Loads and plays the files in assets/audio for [GameAudio]: one Web Audio
/// graph in browsers, audioplayers on phones and desktops.
///
/// Names are file names without `.mp3`. Volumes are linear gains (1 is the
/// level the file was made at) and pans go from -1 (left) to 1 (right).
abstract interface class AudioEngine {
  factory AudioEngine() => platform.createEngine();

  /// Starts the music at [music] and the wind loop silent, and loads
  /// [effects] in the background. Call it from a tap: browsers only let
  /// sound start after the player has touched the page.
  Future<void> start(List<String> effects, {required double music});

  /// Plays an effect. One that has not loaded yet is skipped.
  void play(String effect, {required double volume, required double pan});

  /// Music volume; 0 stops it. [muffled] makes it quieter and darker (pause).
  void setMusic(double volume, {required bool muffled});

  void setWind(double volume);

  /// Silence everything while the app is in the background, and come back.
  void suspend();
  void resume();
}
