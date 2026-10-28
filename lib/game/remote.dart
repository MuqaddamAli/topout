// Other climbers in an online room. Each game sends a small state of its
// climber about 10 times a second; here those states are read, kept for a
// moment and played back a little in the past, blended between the two
// states around that moment, so the climbers move smoothly.
import 'dart:math' as math;

import 'body.dart';
import 'core.dart';
import 'online.dart';
import 'palette.dart';
import 'walk.dart';

/// One moment of a climber, as sent over the network. On the wire it is
/// one JSON array (see server/bots.js):
///   [t, climber, cx, cy, tilt, lookX, lookUp,
///    leftHandX, leftHandY, rightHandX, rightHandY, leftFootX, leftFootY, rightFootX, rightFootY,
///    bits, metres, secs]
/// secs (seconds since the room's start) may be missing in older states.
/// bits: see [encode]; 14 standing on a flat hold (walking there is played
/// back from how the body moves), 15 facing left.
class ClimberState {
  ClimberState({
    required this.t,
    required this.climber,
    required this.c,
    required this.tilt,
    required this.lookX,
    required this.lookUp,
    required this.ends,
    required this.styles,
    required this.kinds,
    required this.footFree,
    this.falling = false,
    this.topped = false,
    this.standing = false,
    this.facingLeft = false,
    this.metres = 0,
    this.secs,
  });

  /// The sender's clock in ms (any start; only differences matter).
  final int t;
  final String climber;
  final Pt c;
  final double tilt, lookX, lookUp;

  /// Left hand, right hand, left foot, right foot.
  final List<Pt> ends;
  final List<HandStyle> styles;
  final List<HoldType> kinds;
  final List<bool> footFree;
  final bool falling, topped;

  /// Standing on a flat hold with both hands free (online), facing left or right.
  final bool standing, facingLeft;
  final double metres;

  /// Seconds since this player's climb started (everyone started together).
  final double? secs;

  static double _r(double v, [double k = 10]) => (v * k).roundToDouble() / k;

  List<Object> encode() {
    var bits = styles[0].index | (styles[1].index << 2) | (kinds[0].index << 4) | (kinds[1].index << 7);
    if (footFree[0]) bits |= 1 << 10;
    if (footFree[1]) bits |= 1 << 11;
    if (falling) bits |= 1 << 12;
    if (topped) bits |= 1 << 13;
    if (standing) bits |= 1 << 14;
    if (facingLeft) bits |= 1 << 15;
    return [
      t,
      climber,
      _r(c.x),
      _r(c.y),
      _r(tilt, 1000),
      _r(lookX, 100),
      _r(lookUp, 100),
      for (final e in ends) ...[_r(e.x), _r(e.y)],
      bits,
      _r(metres),
      if (secs != null) _r(secs!),
    ];
  }

  /// Reads a state, or null if it is not one.
  static ClimberState? decode(Object? raw) {
    if (raw is! List || raw.length < 17 || raw[1] is! String) return null;
    final n = <double>[];
    for (final k in [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]) {
      final v = raw[k];
      if (v is! num || !v.isFinite) return null;
      n.add(v.toDouble());
    }
    final bits = n[14].toInt();
    final secs = raw.length > 17 && raw[17] is num ? (raw[17] as num).toDouble() : null;
    HandStyle style(int v) => HandStyle.values[math.min(v, HandStyle.values.length - 1)];
    HoldType kind(int v) => HoldType.values[math.min(v, HoldType.values.length - 1)];
    return ClimberState(
      t: n[0].toInt(),
      climber: raw[1] as String,
      c: Pt(n[1], n[2]),
      tilt: n[3],
      lookX: n[4],
      lookUp: n[5],
      ends: [Pt(n[6], n[7]), Pt(n[8], n[9]), Pt(n[10], n[11]), Pt(n[12], n[13])],
      styles: [style(bits & 3), style((bits >> 2) & 3)],
      kinds: [kind((bits >> 4) & 7), kind((bits >> 7) & 7)],
      footFree: [bits & (1 << 10) != 0, bits & (1 << 11) != 0],
      falling: bits & (1 << 12) != 0,
      topped: bits & (1 << 13) != 0,
      standing: bits & (1 << 14) != 0,
      facingLeft: bits & (1 << 15) != 0,
      metres: n[15],
      secs: secs != null && secs.isFinite ? secs : null,
    );
  }

  /// The state [u] of the way from [a] to [b]. Things that cannot be blended
  /// (which hand grips, which hold) switch halfway.
  static ClimberState lerp(ClimberState a, ClimberState b, double u) {
    // a jump across the wall (a restart, a fall card) is not swept across
    if (hypot(b.c.x - a.c.x, b.c.y - a.c.y) > 250) u = 1;
    final n = u < 0.5 ? a : b;
    Pt p(Pt x, Pt y) => Pt(lerpD(x.x, y.x, u), lerpD(x.y, y.y, u));
    return ClimberState(
      t: lerpD(a.t.toDouble(), b.t.toDouble(), u).round(),
      climber: b.climber,
      c: p(a.c, b.c),
      tilt: lerpD(a.tilt, b.tilt, u),
      lookX: lerpD(a.lookX, b.lookX, u),
      lookUp: lerpD(a.lookUp, b.lookUp, u),
      ends: [for (var i = 0; i < 4; i++) p(a.ends[i], b.ends[i])],
      styles: n.styles,
      kinds: n.kinds,
      footFree: n.footFree,
      falling: n.falling,
      topped: n.topped,
      standing: n.standing,
      facingLeft: n.facingLeft,
      metres: lerpD(a.metres, b.metres, u),
      secs: n.secs,
    );
  }
}

enum RemoteEvent { fell, topped }

/// Another player's climber: the states that came in, and what is drawn now.
class RemoteClimber {
  RemoteClimber(this.id, this.name);
  final String id;
  String name;

  /// How far in the past the climber is shown, in ms.
  static const int delay = 100;

  /// States kept, newest last (about a second's worth).
  final List<ClimberState> states = [];

  /// Recent (arrival time - sender time): the smallest is the quickest trip,
  /// which tells how the sender's clock lines up with ours.
  final List<int> _offsets = [];
  int _offset = 0;

  /// What is drawn this frame (null until the first state comes in).
  ClimberState? shown;
  Pose? pose;
  Gear? gear;
  Look? look;
  String? _gearFor;

  /// Seconds from the room's start to this player's first top-out.
  double? finish;
  bool _wasFalling = false, _wasTopped = false;
  final double _breathAt = math.Random().nextDouble() * 6;

  /// Walking, played back from how the shown body moves: the step cycle,
  /// how much they walk (0 to 1) and where the body was last frame.
  double _phase = 0, _walk = 0;
  double? _lastX;

  void add(ClimberState s, int nowMs) {
    if (states.isNotEmpty && s.t <= states.last.t) return; // late or doubled
    states.add(s);
    while (states.length > 2 && states.last.t - states[1].t > 1000) {
      states.removeAt(0);
    }
    _offsets.add(nowMs - s.t);
    if (_offsets.length > 30) _offsets.removeAt(0);
    _offset = _offsets.reduce(math.min);
  }

  /// The state to show at [nowMs] (our clock): [delay] ms in the past, on
  /// the sender's clock, between the two states around that moment.
  ClimberState? sample(int nowMs) {
    if (states.isEmpty) return null;
    final at = nowMs - _offset - delay;
    if (at <= states.first.t) return states.first;
    if (at >= states.last.t) return states.last; // nothing newer yet: wait there
    var k = states.length - 1;
    while (states[k - 1].t > at) {
      k--;
    }
    final a = states[k - 1], b = states[k];
    return ClimberState.lerp(a, b, (at - a.t) / (b.t - a.t));
  }

  /// Builds the pose to draw and swings the gear. [clock] is in seconds.
  /// Returns a fall or a top-out that happens in what is shown now.
  RemoteEvent? update(int nowMs, double dt, double clock, {bool still = false}) {
    final s = sample(nowMs);
    shown = s;
    if (s == null) return null;
    RemoteEvent? ev;
    if (s.falling && !_wasFalling) ev = RemoteEvent.fell;
    if (s.topped && !_wasTopped) {
      ev = RemoteEvent.topped;
      finish ??= s.secs;
    }
    _wasFalling = s.falling;
    _wasTopped = s.topped;
    final k = Climber.byId(s.climber), lk = look = Look.of(k.id);
    final br = still ? 0.0 : math.sin((clock + _breathAt) * 2.1);
    final Pose p;
    if (s.standing) {
      // the steps come from how far the body moves, so they stay smooth
      final dx = (s.c.x - (_lastX ?? s.c.x)).abs();
      final speed = dt > 0 ? dx / dt : 0.0;
      _walk += (clampD(speed / walkSpeed, 0, 1) - _walk) * math.min(1.0, dt * 8);
      _phase = (_phase + dx / strideLength * 2 * math.pi) % (math.pi * 200);
      final facing = s.facingLeft ? -1.0 : 1.0;
      final sp = standAt(k, s.c.x, math.min(s.ends[2].y, s.ends[3].y), facing: facing, phase: _phase, walk: _walk);
      p = pose = climberPose(k, sp.c, sp.tilt, br, _walk > 0.05 ? facing * 2.2 : s.lookX, s.lookUp, [sp.ends[0], sp.ends[1]],
          const [HandStyle.open, HandStyle.open], s.kinds, [sp.ends[2], sp.ends[3]], [sp.ends[2].y > sp.ends[3].y + 0.5, sp.ends[3].y > sp.ends[2].y + 0.5]);
    } else {
      _walk = 0;
      p = pose = climberPose(k, s.c, s.tilt, br, s.lookX, s.lookUp, [s.ends[0], s.ends[1]], s.styles, s.kinds,
          [s.ends[2], s.ends[3]], s.footFree);
    }
    _lastX = s.c.x;
    // a new climber needs new hair
    if (gear == null || _gearFor != k.id) {
      gear = Gear(p, links: lk.tailLinks, link: lk.tailLink);
      _gearFor = k.id;
    }
    final wind = 25.0 * (0.6 + 0.4 * math.sin(clock * 0.9 + _breathAt));
    gear!.update(p, dt, s.falling ? wind * 4 : wind);
    return ev;
  }
}

/// Everyone else in the room.
class RemoteClimbers {
  final Map<String, RemoteClimber> byId = {};

  Iterable<RemoteClimber> get all => byId.values;
  bool get isEmpty => byId.isEmpty;

  /// Matches the room's player list: adds new players, drops the ones who
  /// left and keeps names up to date. [you] is left out.
  void sync(List<RoomPlayer> players, String? you) {
    final ids = {for (final p in players) p.id};
    byId.removeWhere((id, _) => !ids.contains(id) || id == you);
    for (final p in players) {
      if (p.id == you) continue;
      byId.putIfAbsent(p.id, () => RemoteClimber(p.id, p.name)).name = p.name;
    }
  }

  /// A state that came in for player [id].
  void receive(String id, Object? raw, int nowMs) {
    final r = byId[id], s = ClimberState.decode(raw);
    if (r != null && s != null) r.add(s, nowMs);
  }

  /// Moves everyone and calls [onEvent] for each fall and top-out.
  void update(int nowMs, double dt, double clock,
      {bool still = false, void Function(RemoteClimber who, RemoteEvent e)? onEvent}) {
    for (final r in byId.values) {
      final e = r.update(nowMs, dt, clock, still: still);
      if (e != null) onEvent?.call(r, e);
    }
  }

  void clear() => byId.clear();
}
