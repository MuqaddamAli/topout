import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small key-value store for settings and records. Values are kept as JSON
/// so the keys and shapes match the web prototype.
class Store {
  Store._(this._prefs);

  /// A store that keeps everything in memory (used by tests).
  Store.memory() : _prefs = null;

  final SharedPreferences? _prefs;
  final Map<String, Object?> _cache = {};
  static const _prefix = 'topout.';

  static Future<Store> open() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = Store._(prefs);
      for (final k in prefs.getKeys()) {
        if (!k.startsWith(_prefix)) continue;
        final raw = prefs.getString(k);
        if (raw == null) continue;
        try {
          s._cache[k.substring(_prefix.length)] = jsonDecode(raw);
        } catch (_) {
          // ignore a broken value
        }
      }
      return s;
    } catch (_) {
      return Store.memory();
    }
  }

  bool has(String key) => _cache[key] != null;

  double getNum(String key, double fallback) {
    final v = _cache[key];
    return v is num ? v.toDouble() : fallback;
  }

  bool getBool(String key, bool fallback) {
    final v = _cache[key];
    return v is bool ? v : fallback;
  }

  String? getString(String key) {
    final v = _cache[key];
    return v is String ? v : null;
  }

  Map<String, dynamic>? getMap(String key) {
    final v = _cache[key];
    return v is Map ? v.cast<String, dynamic>() : null;
  }

  void set(String key, Object? value) {
    _cache[key] = value;
    final p = _prefs;
    if (p == null) return;
    // Fire and forget: the cache already holds the value.
    p.setString('$_prefix$key', jsonEncode(value)).catchError((Object _) => false);
  }
}
