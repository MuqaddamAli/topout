import 'core.dart';
import 'store.dart';

/// What the game remembers between visits: the best height and time on
/// each route in each mode, and the climbing log (totals over every climb).
class Records {
  Records(this._store) {
    final l = _store.getMap('log');
    if (l != null) {
      tops = (l['tops'] as num?)?.toInt() ?? 0;
      metres = (l['metres'] as num?)?.toDouble() ?? 0;
      falls = (l['falls'] as num?)?.toInt() ?? 0;
      secs = (l['secs'] as num?)?.toDouble() ?? 0;
    }
  }

  final Store _store;

  // ---- the climbing log
  int tops = 0, falls = 0;
  double metres = 0, secs = 0;

  void saveLog() => _store.set('log', {'tops': tops, 'metres': metres, 'falls': falls, 'secs': secs});

  // ---- best heights (the Daily Wall keeps one per day: [day] is its key)
  final Map<String, double> _heights = {};

  static String _heightKey(ClimbRoute r, Mode mode, String day) => 'height.${r.endless ? 'daily.$day' : r.id}.${mode.name}';
  static String _dailyKey(Mode mode) => 'height.daily.all.${mode.name}';

  double bestHeight(ClimbRoute r, Mode mode, String day) {
    final k = _heightKey(r, mode, day);
    return _heights.putIfAbsent(k, () => _store.getNum(k, 0));
  }

  /// The best height on any Daily Wall.
  double bestEverDaily(Mode mode) => _store.getNum(_dailyKey(mode), 0);

  /// Saves [metres] if it beats the best height.
  void reached(ClimbRoute r, Mode mode, String day, double metres) {
    if (metres > bestHeight(r, mode, day)) {
      final k = _heightKey(r, mode, day);
      _store.set(k, metres);
      _heights[k] = metres;
    }
    if (r.endless && metres > bestEverDaily(mode)) _store.set(_dailyKey(mode), metres);
  }

  // ---- best times
  static String _timeKey(ClimbRoute r, Mode mode) => 'best.${r.id}.${mode.name}';

  double? bestTime(ClimbRoute r, Mode mode) => (_store.getMap(_timeKey(r, mode))?['time'] as num?)?.toDouble();

  /// Who climbed the best time, or null for records from before there were climbers.
  Climber? bestClimber(ClimbRoute r, Mode mode) {
    final id = _store.getMap(_timeKey(r, mode))?['climber'];
    return id is String ? Climber.byId(id) : null;
  }

  void newBestTime(ClimbRoute r, Mode mode, {required double time, required int moves, required Climber climber}) =>
      _store.set(_timeKey(r, mode), {'time': time, 'moves': moves, 'climber': climber.id});
}
