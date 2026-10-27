// The game: state, the 60 Hz simulation, input, falls, records, and the
// climber's pose. Drawing lives in scene.dart and climber.dart; the menus and
// HUD are widgets in lib/ui.
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'audio.dart';
import 'core.dart';
import 'store.dart';

enum Phase { menu, climb, paused, falling, fallCard, top }

/// Which overlay is on screen.
enum Screen { menu, hud, fallCard, topCard, pause }

enum HandStyle { grip, fist, open }

enum HoldStatus { good, weak, no, dyno, far }

enum PartKind { chalk, dust, pebble, snow, spark }

enum ToastKind { plain, warn, ok }

double lerpD(double a, double b, double t) => a + (b - a) * t;

/// A point turned by angle [a] around [c].
Pt rot(Pt c, double a, double dx, double dy) {
  final co = math.cos(a), s = math.sin(a);
  return Pt(c.x + dx * co - dy * s, c.y + dx * s + dy * co);
}

class Snapshot {
  Snapshot(this.limbs, this.c);
  final List<Limb> limbs;
  final Pt c;
}

class Checkpoint {
  Checkpoint(this.snap, this.ledge);
  final Snapshot snap;
  final int ledge;
}

class DragState {
  DragState({
    required this.i,
    required this.from,
    required this.snap,
    required this.start,
    required this.off0,
    required this.offT,
    required this.touch,
  });
  final int i;
  final Limb from;
  final Snapshot snap;
  final Offset start;
  final Offset off0;
  final Offset offT;
  final bool touch;
  double px = 0, py = 0;
  int cand = -1;
  Pt? candPt;
  bool candOk = false;
  DynoResult? candDyno;
  String why = '';
  final Map<int, HoldStatus> status = {};

  /// Where the finger is and where it aims (touch only).
  Offset? finger, aim;
}

class FallInfo {
  FallInfo({
    required this.hang,
    required this.i,
    required this.t,
    required this.feetW,
    required this.hands,
    required this.height,
  });
  final bool hang;
  final int i;
  final HoldType t;
  final double feetW;
  final int hands;
  final double height;
  double reached = 0;
  double prevBest = 0;
}

class FallState {
  FallState(this.info, this.trace);
  final FallInfo info;
  final List<List<double>> trace;
  double v = 0, t = 0;
  bool landed = false;
}

class DynoState {
  DynoState(this.i, this.c0, this.c1, this.pt, this.hold, this.q);
  final int i;
  final Pt c0, c1, pt;
  final int hold;
  final Quality q;
  double t = 0;
  final double dur = 0.45;
}

class Cele {
  Cele(this.c0, this.c1);
  final Pt c0, c1;
  double t = 0;
  bool burst = false;
}

class Particle {
  Particle(this.x, this.y, this.vx, this.vy, this.r, this.max, this.kind);
  double x, y, vx, vy;
  final double r, max;
  final PartKind kind;
  double t = 0;
}

class Bird {
  Bird(this.u, this.h, this.v, this.ph, this.s);
  double u, ph;
  final double h, v, s;
}

class Shake {
  Shake(this.i, this.t);
  final int i;
  double t;
}

class ArmGeo {
  ArmGeo(this.s, this.m, this.w, this.e, this.dir, this.style, this.kind);
  final Pt s, m, w, e, dir;
  final HandStyle style;
  final HoldType kind;
}

class LegGeo {
  LegGeo(this.h, this.k, this.a, this.e, this.free);
  final Pt h, k, a, e;
  final bool free;
}

class Pose {
  Pose(this.c, this.tilt, this.br, this.lookX, this.lookUp);
  final Pt c;
  final double tilt, br, lookX, lookUp;
  late final List<Pt> shoulders;
  late final List<Pt> hips;
  late final Pt head;
  late final List<ArmGeo> arms;
  late final List<LegGeo> legs;
}

class QuickdrawState {
  QuickdrawState(this.p, this.prev);
  final Pt p, prev;
}

/// Things that swing: the ponytail, the chalk bag and the quickdraws.
class Gear {
  final List<Pt> tail = [], tailPrev = [];
  late Pt bag, bagPrev;
  final List<QuickdrawState> qd = [];
}

class FallCardData {
  FallCardData({
    required this.endless,
    required this.value,
    required this.why,
    required this.fix,
    required this.note,
    required this.noteDim,
    required this.retryLabel,
    required this.showRestart,
    required this.trace,
    required this.hand,
  });
  final bool endless;
  final String value;
  final String why;
  final String fix;
  final String? note;
  final bool noteDim;
  final String retryLabel;
  final bool showRestart;
  final List<List<double>> trace;
  final int hand;
}

class TopCardData {
  TopCardData(this.routeName, this.time, this.moves, this.falls, this.note, this.noteDim, this.nextLabel);
  final String routeName, time;
  final int moves, falls;
  final String note;
  final bool noteDim;
  final String nextLabel;
}

class Tick {
  Tick(this.pos, this.hold);
  final double pos;
  final int hold;
}

class _Later {
  _Later(this.at, this.fn);
  final double at;
  final VoidCallback fn;
}

class _Tip {
  const _Tip(this.id, this.text, this.when);
  final String id;
  final String text;
  final bool Function(Game g) when;
}

/// Simple notifier the painter and HUD listen to.
class Pulse extends ChangeNotifier {
  void fire() => notifyListeners();
}

const List<double> qdLen = [10, 12, 10, 12];
const List<List<double>> qdAt = [
  [-12.6, -20.5],
  [-9.4, -21.8],
  [12.6, -20.5],
  [9.4, -21.8],
];

/// The Daily Wall gets snow above this height.
const double snowY = 2000;

const Map<HoldType, String> holdWord = {
  HoldType.jug: 'a big hold',
  HoldType.crimp: 'a small edge',
  HoldType.sloper: 'a round hold',
  HoldType.ledge: 'the ledge',
  HoldType.top: 'the top',
};

String fmtTime(double t) {
  final m = (t / 60).floor(), s = (t % 60).floor();
  return '$m:${s.toString().padLeft(2, '0')}';
}

class Game {
  Game({required this.store, required this.audio, DateTime? today}) {
    final day = today ?? DateTime.now();
    todayKey = dateKey(day);
    routes = [...buildRoutes(), dailyWallFor(day)];
    mode = Mode.fromName(store.getString('mode'));
    final l = store.getMap('log');
    if (l != null) {
      logTops = (l['tops'] as num?)?.toInt() ?? 0;
      logMetres = (l['metres'] as num?)?.toDouble() ?? 0;
      logFalls = (l['falls'] as num?)?.toInt() ?? 0;
      logSecs = (l['secs'] as num?)?.toDouble() ?? 0;
    }
    setMenuPose();
  }

  final Store store;
  final GameAudio audio;
  late final String todayKey;
  late final List<ClimbRoute> routes;
  final _rand = math.Random();

  /// Fires every frame (painter, HUD).
  final Pulse frameTick = Pulse();

  /// Fires when an overlay changes (menu, cards, tips).
  final Pulse uiChanged = Pulse();
  void _ui() => uiChanged.fire();

  bool reducedMotion = false;

  // ---- view
  double cw = 390, ch = 844;
  bool portrait = true;
  double camX = 180, camY = 120, scale = 1;
  double? camManual;
  bool showRecenter = false;

  // ---- state
  Mode mode = Mode.normal;
  ClimbRoute? route;
  Phase phase = Phase.menu;
  Screen screen = Screen.menu;
  List<Limb> limbs = [];
  Pt c = Pt(180, 100), cd = Pt(180, 100);
  List<double> grip = [100, 100], holdTime = [0, 0];
  int moves = 0, falls = 0;
  double time = 0;
  final List<Snapshot> history = [];
  Checkpoint? checkpoint;
  int? cpLedge;
  DragState? drag;
  bool look = false;
  double lookK = 0;
  int? _ptr;
  ({double sy, double cam})? _pan;
  final List<List<double>> trace = [];
  double traceAcc = 0;
  FallState? fall;
  Shake? shake;
  List<Pt> endDraw = [];
  final Map<String, bool> tipsSeen = {};
  String? tipCur;
  double tipShownAt = 0;
  double clock = 0;
  List<Particle> parts = [];
  double camShake = 0;
  DynoState? dyno;
  double hangT = 0;
  bool segOpen = false;
  double maxY = 0, segStartY = 0, segTime = 0;
  double bestAtStart = 0;
  bool newBestShown = false;
  int restLedge = 0;
  final Set<int> lit = {};
  final Map<int, double> litAt = {};
  Set<int> chalked = {};
  double tilt = 0, br = 0, lookX = 0, lookUp = 0;
  List<HandStyle> hStyle = [HandStyle.grip, HandStyle.grip];
  List<HoldType> hKind = [HoldType.jug, HoldType.jug];
  List<bool> fFree = [false, false];
  List<double> freeT = [0, 0];
  int? chalkHand;
  double lastChalk = -9;
  double tremble = 0;
  Gear? gear;
  Pose? pose;
  Cele? cele;
  List<Bird> birds = [];
  double nextFlock = 4;

  // ---- overlay data
  String? tipText;
  String? toastText;
  ToastKind toastKind = ToastKind.plain;
  double toastUntil = 0;
  FallCardData? fallCard;
  TopCardData? topCard;
  List<Tick> ticks = [];
  double _tickSpan = 0;
  ClimbRoute? _tickRoute;

  // ---- records
  int logTops = 0, logFalls = 0;
  double logMetres = 0, logSecs = 0;
  final Map<String, double> _heights = {};

  final List<_Later> _later = [];
  double _acc = 0, _tipAcc = 0;

  List<Hold> get holds => route!.holds;
  ClimbRoute get menuRoute => routes[0];

  // ================================================================ view

  void setViewport(Size size) {
    cw = size.width;
    ch = size.height;
    portrait = ch >= cw * 0.9;
  }

  double baseScale() => portrait
      ? clampD(math.min(cw / 290, ch / 480), 0.8, 2.4)
      : clampD(math.min(cw / 420, (ch - 40) / 560), 0.7, 2.2);

  double lookScale() {
    final r = route;
    if (r == null) return 1;
    return math.min(cw / 390, (ch - 220) / (r.endless ? 1400 : r.topY + 160));
  }

  Offset w2s(double x, double y) => Offset((x - camX) * scale + cw / 2, (camY - y) * scale + ch / 2);
  Pt s2w(double sx, double sy) => Pt((sx - cw / 2) / scale + camX, camY - (sy - ch / 2) / scale);

  ({double x0, double x1, double y0, double y1}) viewRange() {
    final a = s2w(0, 0), b = s2w(cw, ch);
    return (x0: a.x - 20, x1: b.x + 20, y0: b.y - 20, y1: a.y + 20);
  }

  double camXFor(double x) {
    final half = cw / scale / 2, lo = Wall.left + half - 8, hi = Wall.right - half + 8;
    return lo > hi ? (Wall.left + Wall.right) / 2 : clampD(x, lo, hi);
  }

  double panOf(double x) => clampD((x - camX) * scale / (cw * 0.6), -0.8, 0.8);

  // ================================================================ helpers

  List<Anchor> anchors() {
    final a = <Anchor>[];
    for (var i = 0; i < limbs.length; i++) {
      final l = limbs[i];
      if (l.h != null) a.add(Anchor(i, l.x, l.y));
    }
    return a;
  }

  Pt jointAt(int i, [Pt? at]) {
    final p = at ?? cd;
    return Pt(p.x + jointOffset[i][0], p.y + jointOffset[i][1]);
  }

  Snapshot snapshot() => Snapshot(limbs.map((l) => l.copy()).toList(), c.copy());
  double climberHeight() => math.max(0, c.y - 100) / unitsPerMetre;

  void later(double secs, VoidCallback fn) => _later.add(_Later(clock + secs, fn));

  void _runLater() {
    if (_later.isEmpty) return;
    final due = _later.where((l) => l.at <= clock).toList();
    _later.removeWhere((l) => l.at <= clock);
    for (final l in due) {
      l.fn();
    }
  }

  void _play(Sfx s, {double pan = 0}) {
    audio.play(s, pan: pan);
    audio.buzz(s);
  }

  // ================================================================ records

  String _heightKey(ClimbRoute r) => 'height.${r.endless ? 'daily.$todayKey' : r.id}.${mode.name}';

  double bestHeight(ClimbRoute r) {
    final k = _heightKey(r);
    return _heights.putIfAbsent(k, () => store.getNum(k, 0));
  }

  String bestKey(ClimbRoute r) => 'best.${r.id}.${mode.name}';
  double? bestTime(ClimbRoute r) => (store.getMap(bestKey(r))?['time'] as num?)?.toDouble();
  double bestEverDaily() => store.getNum('height.daily.all.${mode.name}', 0);

  void _saveLog() => store.set('log', {'tops': logTops, 'metres': logMetres, 'falls': logFalls, 'secs': logSecs});

  void commitSegment() {
    final r = route;
    if (r == null || !segOpen) return;
    segOpen = false;
    logMetres += math.max(0, maxY - segStartY) / unitsPerMetre;
    logSecs += math.max(0, time - segTime);
    final h = math.max(0, maxY - 100) / unitsPerMetre;
    if (h > bestHeight(r)) {
      store.set(_heightKey(r), h);
      _heights[_heightKey(r)] = h.toDouble();
    }
    if (r.endless) {
      final k = 'height.daily.all.${mode.name}';
      if (h > store.getNum(k, 0)) store.set(k, h);
    }
    _saveLog();
  }

  void openSegment() {
    segOpen = true;
    maxY = c.y;
    segStartY = c.y;
    segTime = time;
  }

  // ================================================================ screens

  void startRoute(ClimbRoute r) {
    commitSegment();
    route = r;
    final h = r.holds;
    final p0 = attachPoint(h[r.startHands[0]], 0), p1 = attachPoint(h[r.startHands[1]], 1);
    limbs = [Limb(r.startHands[0], p0.x, p0.y), Limb(r.startHands[1], p1.x, p1.y), Limb(0, 164, 0), Limb(0, 198, 0)];
    final s = solve(Pt(180, 100), anchors(), 80);
    c = Pt(s.x, s.y);
    cd = c.copy();
    grip = [100, 100];
    holdTime = [0, 0];
    moves = 0;
    time = 0;
    falls = 0;
    history.clear();
    drag = null;
    fall = null;
    look = false;
    lookK = 0;
    camManual = null;
    showRecenter = false;
    cele = null;
    trace.clear();
    traceAcc = 0;
    tipsSeen.clear();
    tipCur = null;
    tipShownAt = 0;
    shake = null;
    parts = [];
    camShake = 0;
    _later.clear();
    endDraw = limbs.map((l) => Pt(l.x, l.y)).toList();
    checkpoint = Checkpoint(snapshot(), 0);
    cpLedge = 0;
    lit.clear();
    litAt.clear();
    chalked = {...r.startHands};
    dyno = null;
    hangT = 0;
    restLedge = 0;
    bestAtStart = bestHeight(r);
    newBestShown = false;
    openSegment();
    resetPoseState([HandStyle.grip, HandStyle.grip]);
    scale = baseScale();
    camX = camXFor(cd.x);
    camY = cd.y + 40;
    phase = Phase.climb;
    _buildTicks();
    screen = Screen.hud;
    fallCard = null;
    topCard = null;
    tipText = null;
    toastText = null;
    audio.muffle(false);
    if (r.tutorial) later(0.5, () => maybeTips(true));
    _ui();
  }

  void resetPoseState(List<HandStyle> styles) {
    tilt = 0;
    br = 0;
    lookX = 0;
    lookUp = 0;
    hStyle = [...styles];
    hKind = [HoldType.jug, HoldType.jug];
    fFree = [false, false];
    freeT = [0, 0];
    chalkHand = null;
    lastChalk = -9;
    tremble = 0;
    gear = null;
    pose = null;
  }

  void setMenuPose() {
    final top = menuRoute.topY;
    const x = 252.0;
    cd = Pt(x, top + 105);
    c = cd.copy();
    endDraw = [Pt(x - 21, top + 82), Pt(x + 21, top + 82), Pt(x - 13, top), Pt(x + 13, top)];
    resetPoseState([HandStyle.fist, HandStyle.fist]);
    lookX = -2.2;
    lookUp = 0.9;
  }

  void showMenu() {
    if (drag != null) endDrag(true);
    commitSegment();
    phase = Phase.menu;
    cele = null;
    parts = [];
    _later.clear();
    setMenuPose();
    screen = Screen.menu;
    tipText = null;
    toastText = null;
    audio.muffle(false);
    _ui();
  }

  void setMode(Mode m) {
    mode = m;
    store.set('mode', m.name);
    _ui();
  }

  void setMusic(bool on) {
    audio.setMusic(on);
    store.set('music', on);
    _ui();
  }

  void setSfx(bool on) {
    audio.setSfx(on);
    store.set('sfx', on);
    _ui();
  }

  void nextRoute() {
    final i = routes.indexOf(route!);
    startRoute(routes[(i + 1) % routes.length]);
  }

  // ================================================================ tips and toasts

  static final List<_Tip> _tips = [
    _Tip('start', 'Drag your right foot up to the small step.', (g) => g.moves == 0),
    _Tip('hands', 'Now move a hand up to a higher hold.', (g) => g.moves >= 1),
    _Tip('feet', 'Keep your feet on the wall. It helps your hands.', (g) => g.moves >= 4),
    _Tip('grip', 'The ring shows how tired a hand is. Let go for a moment to rest it.',
        (g) => math.min(g.grip[0], g.grip[1]) < 80),
    _Tip('ledge', 'Stand on the ledge with both feet. You can rest there.', (g) => g._nextLedgeGap() < 200),
    _Tip('undo', 'Undo takes back your last move.', (g) => g.cpLedge != 0 && g.moves >= 8),
    _Tip('look', 'Tap Look to see the whole wall.', (g) => g.cpLedge != 0 && g.moves >= 11),
    _Tip('top', 'Put both hands on the top.', (g) => g.route!.topY - g.c.y < 230),
  ];

  double _nextLedgeGap() {
    var best = 1e9;
    for (final h in holds) {
      if (h.t == HoldType.ledge && h.y > c.y - 40) best = math.min(best, h.y - c.y);
    }
    return best;
  }

  void maybeTips(bool force) {
    if (route == null || phase != Phase.climb || dyno != null || hangT > 0) return;
    final d = drag;
    if (d != null && d.candDyno != null && !store.getBool('tip.dyno', false)) {
      store.set('tip.dyno', true);
      showTip('Blue holds are far. Let go there to jump. Then grab another hold fast.');
      return;
    }
    if (!route!.tutorial) return;
    final now = clock;
    _Tip? cur;
    for (final t in _tips) {
      if (t.id == tipCur) cur = t;
    }
    final done = cur != null && !cur.when(this);
    if (!force && tipText != null && now - tipShownAt < (done ? 1.2 : 6)) return;
    for (final t in _tips) {
      if (tipsSeen[t.id] == true) continue;
      if (t.when(this)) {
        tipsSeen[t.id] = true;
        tipCur = t.id;
        showTip(t.text);
        return;
      }
    }
  }

  void showTip(String text) {
    tipText = text;
    tipShownAt = clock;
    _ui();
  }

  void hideTip() {
    if (tipText == null) return;
    tipText = null;
    _ui();
  }

  void toast(String msg, [ToastKind kind = ToastKind.plain]) {
    toastText = msg;
    toastKind = kind;
    toastUntil = clock + 2.2;
  }

  bool get toastVisible => toastText != null && clock < toastUntil;

  // ================================================================ particles

  void burst(double x, double y, PartKind kind, int n) {
    for (var k = 0; k < n; k++) {
      final a = _rand.nextDouble() * math.pi * 2;
      final sp = kind == PartKind.pebble ? 20 + _rand.nextDouble() * 30 : 14 + _rand.nextDouble() * 38;
      parts.add(Particle(
        x,
        y,
        math.cos(a) * sp,
        kind == PartKind.pebble ? 10 + _rand.nextDouble() * 25 : (math.sin(a)).abs() * sp * 0.8,
        kind == PartKind.chalk ? 1.4 + _rand.nextDouble() * 2.2 : 1 + _rand.nextDouble() * 2,
        0.5 + _rand.nextDouble() * 0.5,
        kind,
      ));
    }
  }

  void _updateParts(double dt) {
    for (final p in parts) {
      p.t += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.kind == PartKind.pebble) {
        p.vy -= 700 * dt;
      } else if (p.kind == PartKind.snow) {
        p.x += math.sin(p.t * 1.7 + p.r * 3) * 0.25;
      } else {
        p.vx *= 0.9;
        p.vy = p.vy * 0.9 + (p.kind == PartKind.chalk ? 6 : -4) * dt;
      }
    }
    parts.removeWhere((p) => p.t >= p.max);
  }

  // ================================================================ input

  Pt limbEnd(int i) {
    final p = pose;
    if (p != null) return i < 2 ? p.arms[i].e : p.legs[i - 2].e;
    if (i < endDraw.length) return endDraw[i];
    return Pt(limbs[i].x, limbs[i].y);
  }

  int pickLimb(double sx, double sy) {
    var best = -1;
    var bd = math.max(38.0, 22 * scale);
    for (var i = 0; i < 4; i++) {
      final e = limbEnd(i), p = w2s(e.x, e.y), d = hypot(p.dx - sx, p.dy - sy);
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  void pointerDown(int id, Offset pos, bool touch) {
    if (phase != Phase.climb || _ptr != null || dyno != null) return;
    if (look) {
      setLook(false);
      return;
    }
    _ptr = id;
    final i = pickLimb(pos.dx, pos.dy);
    if (i >= 0) {
      _beginDrag(i, pos, touch);
    } else {
      _pan = (sy: pos.dy, cam: camY);
    }
  }

  void pointerMove(int id, Offset pos) {
    if (id != _ptr) return;
    if (drag != null) {
      _updateDrag(pos);
    } else if (_pan != null && route != null) {
      final dy = (pos.dy - _pan!.sy) / scale;
      if (dy.abs() > 4 || camManual != null) {
        camManual = clampD(_pan!.cam + dy, 40, route!.topY + 60);
        if (!showRecenter) {
          showRecenter = true;
          _ui();
        }
      }
    }
  }

  void pointerUp(int id, {bool cancelled = false}) {
    if (id != _ptr) return;
    _ptr = null;
    if (drag != null) endDrag(cancelled);
    _pan = null;
  }

  void recenter() {
    camManual = null;
    showRecenter = false;
    _ui();
  }

  void _beginDrag(int i, Offset pos, bool touch) {
    final l = limbs[i];
    if (l.h != null) {
      final test = [for (var k = 0; k < 4; k++) k == i ? Limb(null, limbs[k].x, limbs[k].y) : limbs[k]];
      if (!supportInfo(test, holds).supported) {
        shake = Shake(i, 0.45);
        _play(Sfx.no);
        toast(hangT > 0 ? 'Get a second hold first.' : 'Hold on with two other limbs first.', ToastKind.warn);
        return;
      }
    }
    final le = limbEnd(i), lp = w2s(le.x, le.y);
    drag = DragState(
      i: i,
      from: l.copy(),
      snap: snapshot(),
      start: pos,
      off0: lp - pos,
      offT: Offset(0, touch ? -math.max(64.0, 30 * scale) : 0),
      touch: touch,
    );
    l.h = null;
    camManual = null;
    if (showRecenter) {
      showRecenter = false;
      _ui();
    }
    _computeStatus();
    _updateDrag(pos);
  }

  void _computeStatus() {
    final d = drag!, h = holds;
    d.status.clear();
    for (var k = 0; k < h.length; k++) {
      final hold = h[k];
      if (holdDist(hold, c.x, c.y) > 230) continue;
      final q = quality(hold, d.i);
      if (q == Quality.no) {
        d.status[k] = HoldStatus.no;
        continue;
      }
      final Pt pt;
      if (hold.t.wide) {
        final j = jointAt(d.i, c);
        pt = attachPoint(hold, d.i, j.x);
      } else {
        pt = attachPoint(hold, d.i);
      }
      if (feasible(limbs, d.i, pt, c) != null) {
        d.status[k] = q == Quality.good ? HoldStatus.good : HoldStatus.weak;
      } else {
        d.status[k] = isHand[d.i] && dynoCheck(limbs, d.i, pt, c).ok ? HoldStatus.dyno : HoldStatus.far;
      }
    }
  }

  void _updateDrag(Offset pos) {
    final d = drag!;
    final moved = (pos - d.start).distance, t = clampD(moved / 34, 0, 1);
    final sx = pos.dx + lerpD(d.off0.dx, d.offT.dx, t), sy = pos.dy + lerpD(d.off0.dy, d.offT.dy, t);
    d.finger = d.touch ? pos : null;
    d.aim = d.touch ? Offset(sx, sy) : null;
    final w = s2w(sx, sy);
    d.px = w.x;
    d.py = w.y;
    final h = holds;
    var best = -1;
    var bd = 30.0;
    for (var k = 0; k < h.length; k++) {
      final dist = holdDist(h[k], w.x, w.y);
      if (dist < bd) {
        bd = dist;
        best = k;
      }
    }
    d.cand = best;
    d.candPt = null;
    d.candOk = false;
    d.candDyno = null;
    if (best >= 0) {
      final hold = h[best], q = quality(hold, d.i), pt = attachPoint(hold, d.i, w.x);
      if (q == Quality.no) {
        d.why = hold.t == HoldType.ground ? '' : (isHand[d.i] ? 'Too small for a hand.' : "Your foot can't go there.");
      } else if (feasible(limbs, d.i, pt, c) == null) {
        final dc = dynoCheck(limbs, d.i, pt, c);
        if (dc.ok) {
          d.candOk = true;
          d.candPt = pt;
          d.candDyno = dc;
          d.why = '';
        } else {
          d.why = isHand[d.i] ? dc.why : 'Too far.';
        }
      } else {
        d.candOk = true;
        d.candPt = pt;
        d.why = '';
      }
    }
  }

  Sfx _grabSound(HoldType t) => t == HoldType.crimp ? Sfx.grabCrimp : (t == HoldType.sloper ? Sfx.grabSloper : Sfx.grabJug);

  void endDrag(bool cancelled) {
    final d = drag!, l = limbs[d.i];
    drag = null;
    if (!cancelled && d.candOk && d.candDyno != null) {
      _startDyno(d);
      return;
    }
    if (!cancelled && d.candOk) {
      l.h = d.cand;
      l.x = d.candPt!.x;
      l.y = d.candPt!.y;
      history.add(d.snap);
      if (history.length > 40) history.removeAt(0);
      moves++;
      if (d.i < 2) {
        holdTime[d.i] = 0;
        chalked.add(d.cand);
      }
      final hand = isHand[d.i];
      burst(l.x, l.y + (hand ? 3 : 0), hand ? PartKind.chalk : PartKind.dust, hand ? 8 : 6);
      _play(hand ? _grabSound(holds[d.cand].t) : Sfx.foot, pan: panOf(l.x));
      _ui();
    } else {
      l.h = d.from.h;
      l.x = d.from.x;
      l.y = d.from.y;
      if (!cancelled && d.cand >= 0 && d.why.isNotEmpty) {
        toast(d.why, ToastKind.warn);
        _play(Sfx.no);
      }
    }
  }

  void _startDyno(DragState d) {
    history.add(d.snap);
    if (history.length > 40) history.removeAt(0);
    moves++;
    for (var k = 0; k < 4; k++) {
      if (k != d.i) limbs[k].h = null;
    }
    dyno = DynoState(d.i, c.copy(), d.candDyno!.end!, d.candPt!, d.cand, quality(holds[d.cand], d.i));
    _play(Sfx.jump, pan: panOf(c.x));
    hideTip();
    _ui();
  }

  bool get canUndo => history.isNotEmpty;

  void undo() {
    if (phase != Phase.climb || drag != null || dyno != null || history.isEmpty) return;
    final s = history.removeLast();
    limbs = s.limbs.map((l) => l.copy()).toList();
    c = s.c.copy();
    holdTime = [0, 0];
    hangT = 0;
    _play(Sfx.foot);
    _ui();
  }

  void setLook(bool on) {
    look = on;
    if (on) tipText = null;
    _ui();
  }

  void pause() {
    if (phase != Phase.climb) return;
    if (drag != null) endDrag(true);
    _ptr = null;
    _pan = null;
    phase = Phase.paused;
    screen = Screen.pause;
    audio.muffle(true);
    _ui();
  }

  void resume() {
    if (phase != Phase.paused) return;
    phase = Phase.climb;
    screen = Screen.hud;
    audio.muffle(false);
    _ui();
  }

  /// Keyboard: U undo, L look, Esc pause, Space or Enter to try again.
  bool key(LogicalKeyboardKey k, {bool ctrl = false}) {
    if (phase == Phase.climb) {
      if (k == LogicalKeyboardKey.keyU || (k == LogicalKeyboardKey.keyZ && ctrl)) {
        undo();
        return true;
      }
      if (k == LogicalKeyboardKey.keyL) {
        setLook(!look);
        return true;
      }
      if (k == LogicalKeyboardKey.escape) {
        pause();
        return true;
      }
    } else if (phase == Phase.fallCard && (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter)) {
      retry();
      return true;
    } else if (phase == Phase.paused && k == LogicalKeyboardKey.escape) {
      resume();
      return true;
    }
    return false;
  }

  // ================================================================ simulation

  void frame(double rawDt) {
    final dt = math.min(0.1, rawDt);
    _acc += dt;
    while (_acc >= 1 / 60) {
      _step(1 / 60);
      _acc -= 1 / 60;
    }
    _animate(dt);
    _runLater();
    _tipAcc += dt;
    if (_tipAcc > 0.5) {
      _tipAcc = 0;
      maybeTips(false);
    }
    if (phase != Phase.paused) {
      audio.ambience(clock, low: phase == Phase.menu || (route != null && cd.y < 500));
    }
    frameTick.fire();
  }

  void _step(double dt) {
    if (phase != Phase.climb) return;
    time += dt;
    if (dyno != null) {
      _stepDyno(dt);
      return;
    }
    final anc = anchors();
    final d = drag;
    if (d != null) anc.add(Anchor(d.i, d.px, d.py, 0.22));
    final sol = solve(c, anc, 24);
    c.x = sol.x;
    c.y = sol.y;
    final g = gripRates(limbs, holds, mode), s = g.s;
    for (var i = 0; i < 2; i++) {
      var r = g.rates[i];
      if (r < 0 && drag != null) r *= slowWhileAiming;
      grip[i] = clampD(grip[i] + r * dt, 0, 100);
      if (limbs[i].h != null) holdTime[i] += dt;
    }
    traceAcc += dt;
    if (traceAcc >= 0.1) {
      traceAcc = 0;
      trace.add([grip[0], grip[1], s.feetW]);
      if (trace.length > 80) trace.removeAt(0);
    }
    for (var i = 0; i < 2; i++) {
      if (limbs[i].h != null && grip[i] <= 0) {
        _releaseHand(i, s);
        if (phase != Phase.climb) return;
      }
    }
    if (hangT > 0) {
      if (supportInfo(limbs, holds).supported) {
        hangT = 0;
      } else {
        hangT -= dt * (drag != null ? slowWhileAiming : 1);
        if (hangT <= 0) {
          hangT = 0;
          final hi = limbs[0].h != null ? 0 : 1, hh = limbs[hi].h;
          _startFall(FallInfo(
            hang: true,
            i: hi,
            t: hh != null ? holds[hh].t : HoldType.jug,
            feetW: 0,
            hands: 1,
            height: climberHeight(),
          ));
          return;
        }
      }
    }
    maxY = math.max(maxY, c.y);
    if (!newBestShown && bestAtStart > 1 && (maxY - 100) / unitsPerMetre > bestAtStart + 0.05) {
      newBestShown = true;
      toast('New best!', ToastKind.ok);
      _play(Sfx.best);
    }
    if (s.standing) _checkpointAt(s);
    final h0 = limbs[0].h, h1 = limbs[1].h;
    if (h0 != null && h1 != null && holds[h0].t == HoldType.top && holds[h1].t == HoldType.top) _topOut();
  }

  void _stepDyno(double dt) {
    final dy = dyno!;
    dy.t += dt;
    final u = math.min(1.0, dy.t / dy.dur), e = 1 - (1 - u) * (1 - u);
    final apex = math.max(dy.c0.y, dy.c1.y) + 36, mx = (dy.c0.x + dy.c1.x) / 2;
    c.x = (1 - e) * (1 - e) * dy.c0.x + 2 * (1 - e) * e * mx + e * e * dy.c1.x;
    c.y = (1 - e) * (1 - e) * dy.c0.y + 2 * (1 - e) * e * apex + e * e * dy.c1.y;
    maxY = math.max(maxY, c.y);
    if (u < 1) return;
    final l = limbs[dy.i];
    l.h = dy.hold;
    l.x = dy.pt.x;
    l.y = dy.pt.y;
    chalked.add(dy.hold);
    grip[dy.i] = math.max(1.0, grip[dy.i] - catchCost[dy.q == Quality.good ? Quality.good : Quality.weak]!);
    holdTime[dy.i] = 0;
    dyno = null;
    hangT = hangTime;
    burst(l.x, l.y + 3, PartKind.chalk, 14);
    camShake = math.max(camShake, 3.0);
    _play(Sfx.catchHold, pan: panOf(l.x));
    toast('Grab another hold!', ToastKind.warn);
    _ui();
  }

  void _releaseHand(int i, Support s) {
    final l = limbs[i], h = holds[l.h!];
    final info = FallInfo(hang: false, i: i, t: h.t, feetW: s.feetW, hands: s.hands, height: climberHeight());
    burst(l.x, l.y, PartKind.pebble, 5);
    camShake = math.max(camShake, 3.0);
    _play(Sfx.slip, pan: panOf(l.x));
    l.h = null;
    holdTime[i] = 0;
    if (drag != null && !supportInfo(limbs, holds).supported) endDrag(true);
    if (!supportInfo(limbs, holds).supported) {
      _startFall(info);
    } else {
      toast('Your ${limbNames[i]} slipped!', ToastKind.warn);
    }
  }

  void _checkpointAt(Support s) {
    var id = s.restIds[0];
    for (final b in s.restIds) {
      if (holds[b].y > holds[id].y) id = b;
    }
    if (id == cpLedge) return;
    if (holds[id].t == HoldType.ground && cpLedge != 0 && cpLedge != null) return;
    cpLedge = id;
    final h = holds[id];
    if (route!.endless) {
      if (h.t == HoldType.ledge && id != restLedge) restLedge = id;
      return;
    }
    if (mode.ledges || h.t == HoldType.ground) {
      checkpoint = Checkpoint(snapshot(), id);
      history.clear();
      if (h.t == HoldType.ledge) {
        lit.add(id);
        litAt[id] = clock;
        toast('Saved', ToastKind.ok);
        burst(h.x + 16, h.y + 10, PartKind.spark, 14);
        _play(Sfx.save, pan: panOf(h.x + 16));
      }
      _ui();
    } else if (h.t == HoldType.ledge) {
      toast('Resting. No saves.', ToastKind.ok);
    }
  }

  void _startFall(FallInfo info) {
    if (drag != null) endDrag(true);
    dyno = null;
    hangT = 0;
    info.reached = math.max(0, maxY - 100) / unitsPerMetre;
    info.prevBest = bestHeight(route!);
    commitSegment();
    logFalls++;
    _saveLog();
    _play(Sfx.fall, pan: panOf(c.x));
    fall = FallState(info, trace.map((e) => [...e]).toList());
    for (final l in limbs) {
      l.h = null;
    }
    falls++;
    phase = Phase.falling;
    look = false;
    tipText = null;
    _ui();
  }

  void retry() {
    if (phase != Phase.fallCard) return;
    final r = route!;
    if (r.endless) {
      startRoute(r);
      return;
    }
    final cp = checkpoint!;
    limbs = cp.snap.limbs.map((l) => l.copy()).toList();
    c = cp.snap.c.copy();
    cd = c.copy();
    endDraw = limbs.map((l) => Pt(l.x, l.y)).toList();
    grip = [100, 100];
    holdTime = [0, 0];
    history.clear();
    trace.clear();
    parts = [];
    cpLedge = cp.ledge;
    fall = null;
    camManual = null;
    dyno = null;
    hangT = 0;
    resetPoseState(limbs.sublist(0, 2).map((l) => l.h != null ? HandStyle.grip : HandStyle.open).toList());
    phase = Phase.climb;
    screen = Screen.hud;
    fallCard = null;
    openSegment();
    bestAtStart = bestHeight(r);
    newBestShown = false;
    _ui();
  }

  /// Start the route again from the ground.
  void restart() => startRoute(route!);

  void _showFallCard() {
    final f = fall!.info, r = route!, endless = r.endless;
    final onSave = !endless && checkpoint!.ledge != 0;
    phase = Phase.fallCard;
    String why, fix;
    if (f.hang) {
      why = 'You caught the jump, but you did not get another hold in time.';
      fix = 'Before you jump, find the next hold.';
    } else {
      why = 'Your ${limbNames[f.i]} got too tired on ${holdWord[f.t] ?? 'a hold'}.';
      if (f.feetW == 0) {
        why += ' Both feet were off the wall.';
      } else if (f.feetW < 1) {
        why += ' Your only foot was on a round hold.';
      } else if (f.feetW < 2) {
        why += ' Only one foot was on the wall.';
      } else if (f.hands == 1) {
        why += ' You held on with one hand.';
      }
      fix = f.feetW < 2
          ? 'Put both feet on holds before you move a hand.'
          : (f.t == HoldType.crimp || f.t == HoldType.sloper)
              ? 'Small and round holds make you tired fast. Move on quickly.'
              : 'Let go of a hold for a moment to rest your hand.';
    }
    String? note;
    var noteDim = false;
    if (endless) {
      if (f.prevBest < 0.05) {
        note = 'Your first try today.';
        noteDim = true;
      } else if (f.reached > f.prevBest + 0.05) {
        note = 'New best today! Before: ${f.prevBest.toStringAsFixed(1)} m';
      } else {
        note = 'Best today: ${f.prevBest.toStringAsFixed(1)} m';
        noteDim = true;
      }
    }
    fallCard = FallCardData(
      endless: endless,
      value: '${(endless ? f.reached : f.height).toStringAsFixed(1)} m',
      why: why,
      fix: fix,
      note: note,
      noteDim: noteDim,
      retryLabel: endless || !onSave ? 'Start again' : 'Try again',
      showRestart: onSave,
      trace: fall!.trace,
      hand: f.i,
    );
    screen = Screen.fallCard;
    _ui();
  }

  void _topOut() {
    phase = Phase.top;
    commitSegment();
    logTops++;
    _saveLog();
    _play(Sfx.top);
    final r = route!, best = bestTime(r);
    final String note;
    final bool isBest;
    if (best == null) {
      isBest = true;
      note = 'Your first time at the top!';
    } else if (time < best) {
      isBest = true;
      note = 'New best time!';
    } else {
      isBest = false;
      note = 'Best time: ${fmtTime(best)}';
    }
    if (isBest) store.set(bestKey(r), {'time': time, 'moves': moves});
    cele = Cele(c.copy(), Pt(clampD(c.x, 70, 290), r.topY + 105));
    for (final l in limbs) {
      l.h = null;
    }
    final t = time, mv = moves, fl = falls;
    later(2.0, () {
      if (route != r || phase != Phase.top) return;
      topCard = TopCardData(
        r.name,
        fmtTime(t),
        mv,
        fl,
        note,
        !isBest,
        routes.indexOf(r) == routes.length - 1 ? 'First route' : 'Next route',
      );
      screen = Screen.topCard;
      _ui();
    });
    _ui();
  }

  // ================================================================ animation

  void _animate(double dt) {
    clock += dt;
    _updateParts(dt);
    _updateBirds(dt);
    camShake = math.max(0.0, camShake - dt * 18);
    br = reducedMotion
        ? 0.0
        : math.sin(clock * ((grip[0] < 40 || grip[1] < 40) && phase == Phase.climb ? 4.4 : 2.1));
    if (phase == Phase.menu) {
      scale = baseScale();
      camX = 180;
      camY = menuRoute.topY - 0.11 * ch / scale;
      lookX = -2.2 + math.sin(clock * 0.3) * 0.5;
      pose = buildPose();
      if (gear == null) _gearInit();
      _gearUpdate(dt);
      audio.setWind(0.05);
      return;
    }
    final r = route;
    if (r == null) return;
    lookK += ((look ? 1 : 0) - lookK) * math.min(1.0, dt * (reducedMotion ? 30 : 7));
    final f = fall;
    final ce = cele;
    if (phase == Phase.falling && f != null) {
      f.t += dt;
      f.v -= 1100 * dt;
      c.y += f.v * dt;
      if (c.y < 64) {
        c.y = 64;
        if (!f.landed) {
          f.landed = true;
          camShake = 7;
          burst(c.x, 4, PartKind.dust, 16);
          _play(Sfx.land, pan: panOf(c.x));
        }
        f.v = 0;
      }
      cd.x = c.x;
      cd.y = c.y;
      if (f.t > 1) _showFallCard();
    } else if (ce != null) {
      ce.t += dt;
      final u = clampD(ce.t / 0.9, 0, 1), e = u * u * (3 - 2 * u);
      c.x = lerpD(ce.c0.x, ce.c1.x, e);
      c.y = lerpD(ce.c0.y, ce.c1.y, e) + math.sin(u * math.pi) * 14;
      final k = math.min(1.0, dt * 18);
      cd.x += (c.x - cd.x) * k;
      cd.y += (c.y - cd.y) * k;
      if (ce.t > 0.9 && !ce.burst) {
        ce.burst = true;
        for (var n = 0; n < 4; n++) {
          later(n * 0.14, () => burst(cd.x + (_rand.nextDouble() - 0.5) * 60, cd.y + 60 + _rand.nextDouble() * 30, PartKind.spark, 12));
        }
      }
    } else {
      final k = math.min(1.0, dt * 18);
      cd.x += (c.x - cd.x) * k;
      cd.y += (c.y - cd.y) * k;
    }
    scale = lerpD(baseScale(), lookScale(), lookK);
    if (drag == null) {
      final normY = camManual ?? cd.y + 40, normX = camXFor(cd.x);
      final lookY = r.endless ? cd.y + 320 : (r.topY + 50) / 2;
      final ty = lerpD(normY, lookY, lookK), tx = lerpD(normX, 180, lookK), e = reducedMotion ? 1.0 : math.min(1.0, dt * 6);
      camY += (ty - camY) * e;
      camX += (tx - camX) * e;
    }
    final sh = shake;
    if (sh != null) {
      sh.t -= dt;
      if (sh.t <= 0) shake = null;
    }
    audio.setWind(phase == Phase.climb ? 0.03 + 0.09 * clampD(cd.y / (r.endless ? 3000 : r.topY), 0, 1) : 0.02);
    final low = math.min(grip[0], grip[1]);
    tremble = phase == Phase.climb && low < 30 ? (30 - low) / 30 * 1.3 : 0.0;
    if (phase == Phase.climb && low < 32) audio.breath((32 - low) / 32, clock);
    if (r.endless && cd.y > snowY - 400 && parts.length < 170 && !reducedMotion) {
      final v = viewRange();
      for (var k = 0; k < 2; k++) {
        parts.add(Particle(v.x0 + _rand.nextDouble() * (v.x1 - v.x0), v.y1, 10 + _rand.nextDouble() * 14,
            -35 - _rand.nextDouble() * 25, 0.8 + _rand.nextDouble() * 1.6, 9, PartKind.snow));
      }
    }
    _limbTargets(dt);
    // body lean: hands over feet
    final e = endDraw;
    final tl = clampD(((e[2].x + e[3].x) - (e[0].x + e[1].x)) * 0.5 * 0.0035, -0.16, 0.16) +
        (phase == Phase.falling ? math.sin(clock * 7) * 0.25 : 0);
    tilt += (tl - tilt) * math.min(1.0, dt * 8);
    // where the head looks
    Pt? tgt;
    if (drag != null) {
      tgt = Pt(drag!.px, drag!.py);
    } else if (dyno != null) {
      tgt = dyno!.pt;
    } else if (cele != null) {
      tgt = Pt(cd.x - 120, cd.y + 160);
    }
    final hx = cd.x, hy = cd.y + 38;
    final lkX = tgt != null ? clampD((tgt.x - hx) * 0.045, -3, 3) : math.sin(clock * 0.35) * 1.2;
    final lkUp = tgt != null ? clampD((tgt.y - hy) * 0.008, -0.6, 1) : 0.5;
    lookX += (lkX - lookX) * math.min(1.0, dt * 6);
    lookUp += (lkUp - lookUp) * math.min(1.0, dt * 6);
    pose = buildPose();
    _gearUpdate(dt);
  }

  void _limbTargets(double dt) {
    if (limbs.length != 4) return;
    final ph = phase, bag = gear?.bag, r = route!;
    for (var i = 0; i < 4; i++) {
      final l = limbs[i], j = jointAt(i, cd), hand = isHand[i];
      double tx, ty;
      var snap = false, free = false;
      var style = HandStyle.open;
      final ce = cele, dy = dyno, d = drag;
      if (ce != null) {
        final u = ce.t;
        if (hand) {
          if (u < 0.55) {
            tx = cd.x + sideOf[i] * 30;
            ty = r.topY;
            style = HandStyle.grip;
          } else {
            tx = cd.x + sideOf[i] * 36;
            ty = cd.y + 84 + math.sin(clock * 6 + i) * 2;
          }
        } else {
          tx = cd.x + sideOf[i] * 14;
          ty = u > 0.5 ? r.topY : j.y - 60;
          free = u <= 0.5;
        }
      } else if (dy != null && dy.i == i) {
        final dx = dy.pt.x - j.x, ddy = dy.pt.y - j.y;
        var len = hypot(dx, ddy);
        if (len == 0) len = 1;
        final m = math.min(1.0, (reach[i] + 2) / len);
        tx = j.x + dx * m;
        ty = j.y + ddy * m;
      } else if (d != null && d.i == i) {
        final target = d.candOk ? d.candPt! : Pt(d.px, d.py);
        final dx = target.x - j.x, ddy = target.y - j.y;
        var len = hypot(dx, ddy);
        if (len == 0) len = 1;
        final m = math.min(1.0, (reach[i] + 2) / len);
        tx = j.x + dx * m;
        ty = j.y + ddy * m;
      } else if (l.h != null) {
        tx = l.x;
        ty = l.y;
        snap = true;
        if (hand) {
          style = HandStyle.grip;
          hKind[i] = holds[l.h!].t;
        }
      } else if (ph == Phase.falling) {
        tx = j.x + sideOf[i] * (hand ? 26 : 16);
        ty = j.y + (hand ? 38 : -52);
        free = true;
      } else if (dy != null) {
        tx = j.x + sideOf[i] * (hand ? 18 : 8);
        ty = j.y + (hand ? -42 : -74);
        free = true;
      } else if (hand && bag != null && ph == Phase.climb && freeT[i] > 0.35 && (chalkHand == null || chalkHand == i)) {
        chalkHand = i;
        style = HandStyle.fist;
        tx = bag.x + sideOf[i] * 2.4;
        ty = bag.y + 3 + (reducedMotion ? 0 : math.max(0, math.sin(clock * 9)) * 1.6);
        final e = endDraw[i];
        if (hypot(e.x - tx, e.y - ty) < 5 && clock - lastChalk > 2.4) {
          lastChalk = clock;
          burst(tx, ty, PartKind.chalk, 6);
          _play(Sfx.chalk, pan: panOf(tx));
        }
      } else {
        tx = j.x + sideOf[i] * (hand ? 9 : 7);
        ty = j.y + (hand ? -50 : -70);
        free = true;
      }
      if (hand) {
        hStyle[i] = style;
        final isFree = l.h == null && !(d != null && d.i == i) && dy == null && ph == Phase.climb;
        freeT[i] = isFree ? freeT[i] + dt : 0.0;
        if (!isFree && chalkHand == i) chalkHand = null;
      } else {
        fFree[i - 2] = free;
      }
      final e = endDraw[i];
      final k = (d != null && d.i == i) || snap ? 1.0 : math.min(1.0, dt * 12);
      e.x += (tx - e.x) * k;
      e.y += (ty - e.y) * k;
    }
  }

  void _updateBirds(double dt) {
    nextFlock -= dt;
    if (nextFlock <= 0) {
      nextFlock = 14 + _rand.nextDouble() * 16;
      final dir = _rand.nextDouble() < 0.5 ? 1.0 : -1.0, n = 3 + _rand.nextInt(3);
      final h = 150 + _rand.nextDouble() * 220, sp = 22 + _rand.nextDouble() * 14;
      for (var k = 0; k < n; k++) {
        birds.add(Bird(
          dir > 0 ? -0.1 - k * 0.03 : 1.1 + k * 0.03,
          h + (k.isOdd ? -10 : 10) * (k / 2).ceil() + _rand.nextDouble() * 6,
          dir * sp / 400,
          _rand.nextDouble() * 6,
          2.6 + _rand.nextDouble() * 1.2,
        ));
      }
    }
    for (final b in birds) {
      b.u += b.v * dt;
      b.ph += dt * 9;
    }
    birds.removeWhere((b) => b.u <= -0.3 || b.u >= 1.3);
  }

  // ================================================================ pose

  static ({Pt mid, Pt end}) _ikJoint(Pt j, Pt e, double a, double b, double side, bool leg) {
    var dx = e.x - j.x, dy = e.y - j.y;
    var d = hypot(dx, dy);
    if (d == 0) d = 1e-6;
    final maxd = a + b - 0.6;
    if (d > maxd) {
      dx *= maxd / d;
      dy *= maxd / d;
      d = maxd;
    }
    d = math.max(d, (a - b).abs() + 0.6);
    final ang = math.acos(clampD((a * a + d * d - b * b) / (2 * a * d), -1, 1)), base = math.atan2(dy, dx);
    final p1 = Pt(j.x + math.cos(base + ang) * a, j.y + math.sin(base + ang) * a);
    final p2 = Pt(j.x + math.cos(base - ang) * a, j.y + math.sin(base - ang) * a);
    double score(Pt p) => side * p.x + (leg ? 0.6 : -0.6) * p.y; // elbows out and down, knees out and up
    return (mid: score(p1) > score(p2) ? p1 : p2, end: Pt(j.x + dx, j.y + dy));
  }

  Pose buildPose() {
    final p = Pose(cd.copy(), tilt, br, lookX, lookUp);
    p.shoulders = [
      for (final i in [0, 1]) (rot(p.c, p.tilt, jointOffset[i][0], jointOffset[i][1])..y += 0.5 * p.br),
    ];
    p.hips = [for (final i in [2, 3]) rot(p.c, p.tilt, jointOffset[i][0], jointOffset[i][1])];
    final hc = rot(p.c, p.tilt, 0, 38.5);
    p.head = Pt(hc.x + p.lookX * 0.5, hc.y + p.lookUp * 1.4 + 0.3 * p.br);
    p.arms = [_armGeo(0, p), _armGeo(1, p)];
    p.legs = [_legGeo(2, p), _legGeo(3, p)];
    return p;
  }

  ArmGeo _armGeo(int i, Pose p) {
    final s = p.shoulders[i], e0 = endDraw[i].copy(), st = hStyle[i];
    if (st == HandStyle.grip && grip[i] < 35 && !reducedMotion && phase == Phase.climb) {
      final amp = (35 - grip[i]) / 35 * 1.6;
      e0.x += math.sin(clock * 47 + i) * amp;
      e0.y += math.cos(clock * 39 + i * 2) * amp * 0.5;
    }
    if (shake != null && shake!.i == i && !reducedMotion) e0.x += math.sin(clock * 60) * 3;
    var dx = e0.x - s.x, dy = e0.y - s.y;
    var d = hypot(dx, dy);
    if (d == 0) d = 1;
    dx /= d;
    dy /= d;
    Pt dir;
    if (st == HandStyle.grip) {
      final bx = dx * 0.4, by = dy * 0.4 + 0.6;
      var bl = hypot(bx, by);
      if (bl == 0) bl = 1;
      dir = Pt(bx / bl, by / bl);
    } else {
      dir = Pt(dx, dy);
    }
    final ik = _ikJoint(s, Pt(e0.x - dir.x * 7, e0.y - dir.y * 7), 34, 26.5, sideOf[i], false);
    final w = ik.end;
    return ArmGeo(s, ik.mid, w, Pt(w.x + dir.x * 7, w.y + dir.y * 7), dir, st, hKind[i]);
  }

  LegGeo _legGeo(int i, Pose p) {
    final h = p.hips[i - 2], e0 = endDraw[i], side = sideOf[i];
    final ik = _ikJoint(h, Pt(e0.x - side * 3.5, e0.y + 6.5), 41, 36, side, true);
    final k = ik.mid.copy();
    if (tremble > 0 && !reducedMotion) k.x += math.sin(clock * 41 + i * 1.7) * tremble;
    final a = ik.end;
    return LegGeo(h, k, a, Pt(a.x + side * 3.5, a.y - 6.5), fFree[i - 2]);
  }

  Pt tailRoot(Pose p) {
    final o = rot(Pt(0, 0), p.tilt * 0.5, -p.lookX * 0.8, -8.2);
    return Pt(p.head.x + o.x, p.head.y + o.y);
  }

  Pt bagAnchor(Pose p) => rot(p.c, p.tilt, 0, -21);
  Pt qdAnchor(Pose p, int k) => rot(p.c, p.tilt, qdAt[k][0], qdAt[k][1]);

  void _gearInit() {
    final p = pose = buildPose(), root = tailRoot(p), g = gear = Gear();
    for (var k = 0; k < 5; k++) {
      final q = Pt(root.x, root.y - k * 3.5);
      g.tail.add(q);
      g.tailPrev.add(q.copy());
    }
    final ba = bagAnchor(p);
    g.bag = Pt(ba.x, ba.y - 7);
    g.bagPrev = g.bag.copy();
    for (var k = 0; k < qdLen.length; k++) {
      final a = qdAnchor(p, k), q = Pt(a.x, a.y - qdLen[k]);
      g.qd.add(QuickdrawState(q, q.copy()));
    }
  }

  static void _verlet(Pt p, Pt prev, double ax, double ay, double h, double damp) {
    final vx = (p.x - prev.x) * damp, vy = (p.y - prev.y) * damp;
    prev.x = p.x;
    prev.y = p.y;
    p.x += vx + ax * h * h;
    p.y += vy + ay * h * h;
  }

  static void _tie(Pt a, Pt p, double len) {
    final dx = p.x - a.x, dy = p.y - a.y;
    var d = hypot(dx, dy);
    if (d == 0) d = 1e-6;
    p.x = a.x + dx / d * len;
    p.y = a.y + dy / d * len;
  }

  void _gearUpdate(double dt) {
    if (gear == null) _gearInit();
    final p = pose!, g = gear!, h = math.min(dt, 1 / 30), damp = math.pow(0.965, h * 60).toDouble();
    final windy = phase == Phase.menu || cele != null;
    final wind = (windy ? 360.0 : 25.0) * (0.6 + 0.4 * math.sin(clock * 0.9)) + (windy ? 90 * math.sin(clock * 3.1) : 0.0);
    final root = tailRoot(p);
    g.tail[0]
      ..x = root.x
      ..y = root.y;
    g.tailPrev[0]
      ..x = root.x
      ..y = root.y;
    for (var k = 1; k < g.tail.length; k++) {
      _verlet(g.tail[k], g.tailPrev[k], wind, -900, h, damp);
    }
    for (var it = 0; it < 3; it++) {
      for (var k = 1; k < g.tail.length; k++) {
        _tie(g.tail[k - 1], g.tail[k], 3.5);
      }
    }
    _verlet(g.bag, g.bagPrev, wind * 0.15, -900, h, damp);
    _tie(bagAnchor(p), g.bag, 7);
    for (var k = 0; k < g.qd.length; k++) {
      final q = g.qd[k];
      _verlet(q.p, q.prev, wind * 0.1, -900, h, damp);
      _tie(qdAnchor(p, k), q.p, qdLen[k]);
    }
  }

  // ================================================================ HUD data

  double progSpan() {
    final r = route!;
    return r.endless
        ? math.max(10.0, (math.max(bestHeight(r), climberHeight()) + 4).ceilToDouble())
        : r.topY / unitsPerMetre;
  }

  void _buildTicks() {
    final r = route!, span = progSpan();
    _tickSpan = span;
    _tickRoute = r;
    ticks = [];
    for (var k = 0; k < r.holds.length; k++) {
      final h = r.holds[k];
      if (h.t != HoldType.ledge) continue;
      final m = (h.y - 100) / unitsPerMetre;
      if (m > span) continue;
      ticks.add(Tick(m / span, k));
    }
  }

  /// Keeps the ledge marks on the progress bar in step with the Daily Wall.
  void refreshTicks() {
    if (route == null) return;
    final span = progSpan();
    if (_tickRoute != route || (span - _tickSpan).abs() > 0.5) _buildTicks();
  }

  String get pillText {
    if (phase == Phase.climb && hangT > 0) return 'Grab a hold!';
    if (phase == Phase.climb && route != null && supportInfo(limbs, holds).standing && c.y > 120) return 'Resting';
    return '';
  }
}
