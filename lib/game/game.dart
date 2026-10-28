// The game: state, the 60 Hz simulation, input, falls and the climber's
// pose. Records live in records.dart and the ambient effects in effects.dart;
// drawing lives in scene.dart and climber.dart; the menus and HUD are widgets
// in lib/ui.
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'audio.dart';
import 'body.dart';
import 'core.dart';
import 'effects.dart';
import 'online.dart';
import 'palette.dart';
import 'records.dart';
import 'remote.dart';
import 'walk.dart';
import 'store.dart';

export 'body.dart';

enum Phase { menu, climb, paused, falling, fallCard, top }

/// Which overlay is on screen.
enum Screen { menu, online, hud, fallCard, topCard, pause, results }

enum HoldStatus { good, weak, no, dyno, far }

enum ToastKind { plain, warn, ok }

class Snapshot {
  Snapshot(this.limbs, this.c, [this.stand]);
  final List<Limb> limbs;
  final Pt c;

  /// The flat hold the climber stood on (online only), or null while climbing.
  final int? stand;
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

  /// Seconds since the drag began (the aiming marks fade in).
  double age = 0;
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

  /// The hand that let go had caught this fall's hold while falling.
  bool afterCatch = false;
}

/// A hold a falling hand could catch right now.
class SnatchOption {
  SnatchOption(this.hold, this.i, this.pt, this.cost, this.left);
  final int hold, i;
  final Pt pt;
  final double cost;

  /// Grip the hand would have left after the catch. At 0 or less it cannot hold on.
  final double left;
}

class FallState {
  FallState(this.info, this.trace, {required this.chance});
  final FallInfo info;
  final List<List<double>> trace;
  double v = 0, t = 0;
  bool landed = false;

  /// One try to catch a hold: true until it is used or the moment passes.
  bool chance;

  /// Time runs slow and the holds in reach glow.
  bool window = false;

  /// The window opened during this fall (and so the fall card can teach it).
  bool offered = false;

  /// How fast the fall runs: 1 normally, the mode's slow motion in the window.
  double slow = 1;

  /// The holds in reach right now. Counted as a fall yet?
  List<SnatchOption> options = const [];
  bool counted = false;

  /// The easiest catch in reach, or null.
  SnatchOption? get best {
    SnatchOption? b;
    for (final o in options) {
      if (b == null || o.left > b.left) b = o;
    }
    return b;
  }
}

/// The white ring where a falling hand caught a hold.
class CatchFlash {
  CatchFlash(this.at);
  final Pt at;
  double t = 0;
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

class Shake {
  Shake(this.i, this.t);
  final int i;
  double t;
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
  TopCardData(this.routeName, this.seconds, this.moves, this.falls, this.note, this.noteDim, this.nextLabel, this.climber);
  final String routeName, climber;
  final double seconds;
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

/// The Daily Wall gets snow above this height.
const double snowY = 2000;

const Map<HoldType, String> holdWord = {
  HoldType.jug: 'a big hold',
  HoldType.crimp: 'a small edge',
  HoldType.sloper: 'a round hold',
  HoldType.ledge: 'the ledge',
  HoldType.top: 'the top',
};

/// One climber in the online standings (the heights list and the finishing order).
class Standing {
  Standing(this.id, this.name, {required this.metres, this.finish, this.you = false, this.connected = true});
  final String id, name;
  final double metres;

  /// Seconds from the start to the first top-out, or null while climbing.
  final double? finish;
  final bool you, connected;
}

/// 1st, 2nd, 3rd, 4th...
String ordinal(int n) {
  final teen = n % 100 >= 11 && n % 100 <= 13;
  return '$n${teen ? 'th' : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' }}';
}

String fmtTime(double t) {
  final m = (t / 60).floor(), s = (t % 60).floor();
  return '$m:${s.toString().padLeft(2, '0')}';
}

class Game {
  Game({required this.store, required this.audio, DateTime? today, NetLink Function()? netLink})
      : _fixedDay = today,
        online = Online(netLink ?? () => SocketLink(mpServer)) {
    online.addListener(_onlineChanged);
    online.onState = (id, s) => remotes.receive(id, s, _netMs.round());
    final day = today ?? DateTime.now();
    todayKey = dateKey(day);
    routes = [...buildRoutes(), dailyWallFor(day)];
    mode = Mode.fromName(store.getString('mode'));
    climber = Climber.byId(store.getString('climber'));
    outfit = Look.of(climber.id);
    setMenuPose();
  }

  final Store store;
  final GameAudio audio;
  late final Records records = Records(store);
  final Effects effects = Effects();

  /// Rooms for climbing with others. Connects only when Play online opens.
  final Online online;

  /// The other climbers in the room.
  final RemoteClimbers remotes = RemoteClimbers();

  /// This climb was started from an online room.
  bool onlineClimb = false;

  /// Where you start online: your lane and side, given by the server at the
  /// start. Null when climbing alone (you start on the route's start holds).
  Spawn? spawn;

  // ---- standing and walking (online, and alone with ?lanes; see walk.dart)

  /// The flat hold (the ground, a ledge or the top) you stand on with both
  /// hands free, or null while climbing.
  int? standOn;

  /// Which way you face (-1 left, 1 right), the step cycle and how much you
  /// walk now (0 still, 1 full stride).
  double facing = 1, walkPhase = 0, walkAmt = 0;
  double _walkV = 0;

  /// Where a finger held beside the climber wants to walk to.
  double? walkTo;
  ({double sy, double at})? _walkHold;

  /// Walk keys held down: -1 left, 1 right.
  final Set<int> _walkKeys = {};

  /// With others the climb goes on after the top: you reached it (your time
  /// stopped), and the top hold you will stand on once the cheer is over.
  bool toppedOut = false;
  int? _celeStand;

  /// The room's climb you are in (Play again starts the next one).
  int _roundPlayed = 0;

  /// Standing and walking are for climbs with others: online, or on a wall
  /// with lanes. A climb alone stays as it always was.
  bool get social => onlineClimb || (route?.lanes.length ?? 1) > 1;

  /// Seconds until the room's climb starts (after the creator taps Start).
  double? countdown;
  int _startsSeen = 0;

  /// Our clock for climber states, in ms, and the time since the last one went out.
  double _netMs = 0, _sendAcc = 0;

  /// The mode picked on the title screen, while a room's mode is in use.
  Mode? _modeBefore;

  /// When the room's climb started (on [_netMs]), and your first top-out
  /// in seconds from then.
  double _onlineStart = 0;
  double? myFinish;

  /// Everyone in the room, finished first (in order) and then highest
  /// first. Updated a few times a second; [standingsChanged] fires on a change.
  List<Standing> standings = const [];
  final Pulse standingsChanged = Pulse();
  double _standAcc = 0;
  String _standKey = '';

  /// Who was in the room at the last update, to tell who joined or left.
  Map<String, RoomPlayer> _known = {};
  String? _knownRoom;

  /// Set by tests to pin the Daily Wall to one day.
  final DateTime? _fixedDay;
  late String todayKey;
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
  Climber climber = Climber.base;
  Look outfit = Look.of(Climber.base.id);
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
  double camShake = 0;
  DynoState? dyno;
  double hangT = 0;

  /// What [hangT] started from (the hang ring shows the share left).
  double hangMax = 1;

  /// Hanging from a hold caught in a fall: a fall now cannot be caught again.
  bool _snatchHang = false;

  /// After a catch the body swings under the hand: the offset it started from.
  ({double dx, double dy, double dip, double t})? _swing;
  CatchFlash? catchFlash;
  bool segOpen = false;
  double maxY = 0, segStartY = 0, segTime = 0;
  double bestAtStart = 0;
  bool newBestShown = false;

  /// Whether this climb goes into the records (best times, highest point,
  /// Daily best, the log). Online climbs and walls with lanes do not.
  bool keepsRecords = true;
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
  double lastChalk = -9, lastChalkSound = -9;
  double tremble = 0;
  Gear? gear;
  Pose? pose;
  Cele? cele;

  /// A dark veil over the scene that lifts after the view jumps (a new route,
  /// the title screen), from 1 down to 0.
  double curtain = 1;

  /// A red glow at the edges of the screen after a hand slips, from 1 down to 0.
  double slipFlash = 0;

  /// Time since a climber was picked on the title screen (they hop).
  double _menuHop = 9;
  bool _menuLanded = true;

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

  final List<_Later> _later = [];
  double _acc = 0, _tipAcc = 0, _coveredFor = 0;

  /// When each hold was last grabbed, for the little give it shows.
  final Map<int, double> _grabbedAt = {};

  void _grabbed(int k) {
    _grabbedAt.removeWhere((_, t) => clock - t > 1);
    _grabbedAt[k] = clock;
  }

  /// How much hold [k] is squashed by a grab right now, 0 to about 0.6.
  double grabPulse(int k) {
    final t = _grabbedAt[k];
    if (t == null || reducedMotion) return 0;
    final u = (clock - t) / 0.3;
    return u >= 1 || u < 0 ? 0 : math.sin(u * math.pi) * (1 - u);
  }

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
    final r = route, left = r?.wallLeft ?? Wall.left, right = r?.wallRight ?? Wall.right;
    final half = cw / scale / 2, lo = left + half - 8, hi = right - half + 8;
    return lo > hi ? (left + right) / 2 : clampD(x, lo, hi);
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

  Snapshot snapshot() => Snapshot(limbs.map((l) => l.copy()).toList(), c.copy(), standOn);
  double climberHeight() {
    // standing, you are as high as what you stand on (the ground is 0 m)
    if (standOn case final s?) return holds[s].y / unitsPerMetre;
    return math.max(0, c.y - 100) / unitsPerMetre;
  }

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

  // Records for the current mode (and, on the Daily Wall, today).
  double bestHeight(ClimbRoute r) => records.bestHeight(r, mode, todayKey);
  double? bestTime(ClimbRoute r) => records.bestTime(r, mode);
  Climber? bestClimber(ClimbRoute r) => records.bestClimber(r, mode);
  double bestEverDaily() => records.bestEverDaily(mode);

  /// Adds the climbing since [openSegment] to the log and the best height.
  void commitSegment() {
    final r = route;
    if (r == null || !segOpen) return;
    segOpen = false;
    if (!keepsRecords) return;
    records.metres += math.max(0, maxY - segStartY) / unitsPerMetre;
    records.secs += math.max(0, time - segTime);
    records.reached(r, mode, todayKey, math.max(0, maxY - 100) / unitsPerMetre);
    records.saveLog();
  }

  void openSegment() {
    segOpen = true;
    maxY = c.y;
    segStartY = c.y;
    segTime = time;
  }

  // ================================================================ screens

  /// Where [r] is in [routes]. A wall with lanes is a copy, so this goes by id.
  int _routeIndex(ClimbRoute r) => routes.indexWhere((x) => x.id == r.id);

  /// For testing a wide wall alone (`?lanes=N` on the web): climbs alone
  /// start on a wall with this many lanes. Not saved in the records.
  int debugLanes = 1;

  void startRoute(ClimbRoute r) {
    if (debugLanes > 1 && !onlineClimb && r.lanes.length == 1) r = laneWall(r, debugLanes);
    commitSegment();
    route = r;
    keepsRecords = !onlineClimb && r.lanes.length == 1;
    final h = r.holds, at = onlineClimb ? spawn : (r.lanes.length > 1 ? r.lanes[0].spawns[0] : null);
    standOn = null;
    _walkV = walkAmt = walkPhase = 0;
    _walkKeys.clear();
    walkTo = null;
    toppedOut = false;
    _celeStand = null;
    if (at != null) {
      // with others: standing on the ground at your spawn, free to walk
      _standOn(0, at.x);
    } else {
      final p0 = attachPoint(h[r.startHands[0]], 0), p1 = attachPoint(h[r.startHands[1]], 1);
      limbs = [Limb(r.startHands[0], p0.x, p0.y), Limb(r.startHands[1], p1.x, p1.y), Limb(0, 164, 0), Limb(0, 198, 0)];
      final s = solve(Pt(180, 100), anchors(), 80);
      c = Pt(s.x, s.y);
    }
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
    effects.parts.clear();
    camShake = 0;
    _later.clear();
    endDraw = limbs.map((l) => Pt(l.x, l.y)).toList();
    checkpoint = Checkpoint(snapshot(), 0);
    cpLedge = 0;
    lit.clear();
    litAt.clear();
    _grabbedAt.clear();
    chalked = at != null ? {} : {...r.startHands};
    dyno = null;
    hangT = 0;
    _clearCatch();
    restLedge = 0;
    bestAtStart = bestHeight(r);
    newBestShown = false;
    openSegment();
    resetPoseState([for (final l in limbs.take(2)) l.h != null ? HandStyle.grip : HandStyle.open]);
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
    curtain = 1;
    slipFlash = 0;
    _ui();
  }

  /// Stands up on flat hold [hold] with the body over [x]: both feet on it,
  /// both hands free.
  void _standOn(int hold, double x) {
    final h = holds[hold], w = walkRange(route!, h);
    final p = standAt(climber, clampD(x, w.lo, w.hi), h.y, facing: facing);
    standOn = hold;
    _walkV = walkAmt = 0;
    c = p.c.copy();
    limbs = [
      Limb(null, p.ends[0].x, p.ends[0].y),
      Limb(null, p.ends[1].x, p.ends[1].y),
      Limb(hold, c.x - 12, h.y),
      Limb(hold, c.x + 12, h.y),
    ];
    hangT = 0;
  }

  /// Walks along the flat hold you stand on: keys, or toward a finger held
  /// beside the climber. Stops at the ends of a ledge.
  void _stepStand(double dt) {
    final h = holds[standOn!], w = walkRange(route!, h);
    var dir = 0.0;
    if (walkTo case final to?) {
      final d = to - c.x;
      dir = d.abs() < 6 ? 0 : d.sign;
    } else {
      dir = (_walkKeys.contains(1) ? 1.0 : 0.0) - (_walkKeys.contains(-1) ? 1.0 : 0.0);
    }
    if (dir != 0) facing = dir;
    _walkV += (dir * walkSpeed - _walkV) * math.min(1.0, dt * 8);
    var x = c.x + _walkV * dt;
    if (x <= w.lo || x >= w.hi) {
      x = clampD(x, w.lo, w.hi);
      _walkV = 0;
    }
    walkPhase = (walkPhase + _walkV.abs() * dt / strideLength * 2 * math.pi) % (math.pi * 200);
    walkAmt = clampD(_walkV.abs() / walkSpeed, 0, 1);
    final p = standAt(climber, x, h.y, facing: facing, phase: walkPhase, walk: walkAmt);
    c
      ..x = p.c.x
      ..y = p.c.y;
    for (var i = 0; i < 2; i++) {
      limbs[i]
        ..x = p.ends[i].x
        ..y = p.ends[i].y;
      limbs[i + 2]
        ..x = x + sideOf[i + 2] * 12
        ..y = h.y;
    }
    final g = gripRates(limbs, holds, mode, climber);
    for (var i = 0; i < 2; i++) {
      grip[i] = clampD(grip[i] + g.rates[i] * dt, 0, 100);
    }
    if (g.s.standing) _checkpointAt(g.s);
  }

  /// After a foot move: with both feet on the same flat hold (the ground or
  /// a ledge), you stand up there and the hands let go.
  void _maybeStand() {
    final a = limbs[2].h, b = limbs[3].h;
    if (!social || a == null || a != b) return;
    if (holds[a].t == HoldType.top && !toppedOut) _reachedTop();
    _standOn(a, (limbs[2].x + limbs[3].x) / 2);
    resetPoseState([HandStyle.open, HandStyle.open]);
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
    lastChalk = lastChalkSound = -9;
    tremble = 0;
    gear = null;
    pose = null;
  }

  void setMenuPose() {
    endDraw = [for (var i = 0; i < 4; i++) Pt(0, 0)];
    _placeMenuClimber(0);
    c = cd.copy();
    resetPoseState([HandStyle.fist, HandStyle.fist]);
    lookX = -2.2;
    lookUp = 0.9;
  }

  /// The climber on the summit of the title screen, [hop] units off the ground.
  void _placeMenuClimber(double hop) {
    final top = menuRoute.topY;
    const x = 252.0;
    cd = Pt(x, top + standHeight(climber) + hop);
    final e = endDraw;
    e[0]
      ..x = x - 21
      ..y = cd.y - 23;
    e[1]
      ..x = x + 21
      ..y = cd.y - 23;
    e[2]
      ..x = x - 13
      ..y = top + hop * 0.85;
    e[3]
      ..x = x + 13
      ..y = top + hop * 0.85;
  }

  /// Picks the climber for the next climbs. Only on the title screen, where they hop and chalk up.
  void setClimber(Climber k) {
    if (k == climber || phase != Phase.menu) return;
    climber = k;
    outfit = Look.of(k.id);
    store.set('climber', k.id);
    online.pick(k.id);
    setMenuPose(); // the hair and the height are different
    _menuHop = 0;
    _menuLanded = false;
    effects.burst(cd.x, cd.y - 18, PartKind.chalk, 10);
    _play(Sfx.chalk, pan: panOf(cd.x));
    _ui();
  }

  void showMenu() {
    if (drag != null) endDrag(true);
    commitSegment();
    _refreshDaily();
    phase = Phase.menu;
    cele = null;
    effects.parts.clear();
    _later.clear();
    setMenuPose();
    curtain = 1;
    slipFlash = 0;
    screen = Screen.menu;
    tipText = null;
    toastText = null;
    audio.muffle(false);
    _ui();
  }

  /// The Play online screen (over the title scene): connects to the server.
  void showOnline() {
    if (phase != Phase.menu) return;
    _refreshDaily();
    screen = Screen.online;
    online.connect();
    _ui();
  }

  void _onlineChanged() {
    final r = online.room;
    if (r == null) {
      remotes.clear();
      countdown = null;
      _known = {};
      _knownRoom = null;
    } else {
      remotes.sync(r.players, online.you);
      _roomNews(r);
      _updateStandings();
    }
    if (online.starts != _startsSeen) {
      _startsSeen = online.starts;
      final next = r != null && onlineClimb && online.startedRound > _roundPlayed;
      if (r != null && ((phase == Phase.menu && screen == Screen.online) || next)) countdown = (online.startsInMs ?? 0) / 1000;
    }
    // the room's climb is over: everyone sees the results
    if (r != null && r.ended && onlineClimb && screen != Screen.results && countdown == null) _showResults();
  }

  /// Messages for who joined, left, dropped out or came back. Several at
  /// once make one message ("Cy and Dee left").
  void _roomNews(RoomView r) {
    final now = {for (final p in r.players) p.id: p};
    if (_knownRoom == r.code) {
      final joined = <String>[], left = <String>[], lost = <String>[], back = <String>[];
      for (final p in r.players) {
        if (p.id == online.you) continue;
        final was = _known[p.id];
        if (was == null) {
          joined.add(p.name);
        } else if (was.connected && !p.connected) {
          lost.add(p.name);
        } else if (!was.connected && p.connected) {
          back.add(p.name);
        }
      }
      for (final p in _known.values) {
        if (!now.containsKey(p.id) && p.id != online.you) left.add(p.name);
      }
      String names(List<String> n) => n.length == 1 ? n[0] : '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
      final news = [
        if (joined.isNotEmpty) '${names(joined)} joined',
        if (back.isNotEmpty) '${names(back)} ${back.length == 1 ? 'is' : 'are'} back',
        if (left.isNotEmpty) '${names(left)} left',
        if (lost.isNotEmpty) '${names(lost)} lost the connection',
      ];
      if (news.isNotEmpty) toast(news.join(' · '), lost.isNotEmpty ? ToastKind.warn : ToastKind.plain);
    }
    _known = now;
    _knownRoom = r.code;
  }

  /// Seconds since the room's climb started.
  double get onlineSecs => (_netMs - _onlineStart) / 1000;

  void _remoteEvent(RemoteClimber who, RemoteEvent e) {
    if (e == RemoteEvent.fell) {
      toast('${who.name} fell', ToastKind.warn);
      return;
    }
    final f = who.finish;
    if (f == null) {
      toast('${who.name} topped out!', ToastKind.ok);
      return;
    }
    final place = [myFinish, for (final o in remotes.all) o.finish].where((x) => x != null && x <= f).length;
    toast('${who.name} topped out! ${ordinal(place)} · ${fmtTime(f)}', ToastKind.ok);
    _updateStandings();
  }

  void _updateStandings() {
    final r = online.room;
    final list = <Standing>[];
    if (onlineClimb && r != null) {
      for (final p in r.players) {
        if (p.id == online.you) {
          list.add(Standing(p.id, p.name, metres: climberHeight(), finish: myFinish, you: true));
        } else {
          final o = remotes.byId[p.id];
          list.add(Standing(p.id, p.name, metres: o?.shown?.metres ?? 0, finish: p.finish ?? o?.finish, connected: p.connected));
        }
      }
      list.sort((a, b) {
        final fa = a.finish, fb = b.finish;
        if (fa != null || fb != null) return fa == null ? 1 : (fb == null ? -1 : fa.compareTo(fb));
        return b.metres.compareTo(a.metres);
      });
    }
    final key = list.map((x) => '${x.id}:${x.name}:${x.metres.toStringAsFixed(1)}:${x.finish}:${x.connected}').join('|');
    if (key == _standKey) return;
    _standKey = key;
    standings = list;
    standingsChanged.fire();
  }

  /// The route of room [r]. The Daily Wall is the one of the creator's day.
  ClimbRoute roomRoute(RoomView r) {
    if (r.route == 'daily') {
      final day = DateTime.tryParse(r.dateKey);
      return day == null || r.dateKey == todayKey ? routes.last : dailyWallFor(day);
    }
    return routes.firstWhere((x) => x.id == r.route, orElse: () => routes.first);
  }

  /// The wall of room [r]: its route with one lane per two players, as
  /// many as the server fixed at the start.
  ClimbRoute roomWall(RoomView r) => laneWall(roomRoute(r), r.laneCount);

  /// Your spawn on [wall]: the lane and side the server gave you.
  Spawn roomSpawn(RoomView r, ClimbRoute wall) {
    final me = r.player(online.you) ?? r.players.first, at = r.slot(me);
    return wall.lanes[math.min(at.lane, wall.lanes.length - 1)].spawns[at.side];
  }

  /// The finishing order and times for everyone, when the room's climb ends.
  void _showResults() {
    if (drag != null) endDrag(true);
    _ptr = null;
    _pan = null;
    _walkHold = null;
    walkTo = null;
    _walkKeys.clear();
    look = false;
    tipText = null;
    _updateStandings();
    screen = Screen.results;
    _ui();
  }

  /// The creator ends the climb for everyone, or after the results starts
  /// the next one (Play again).
  void endClimb() => online.endClimb();
  void playAgain() => online.again();

  /// Everyone in the room starts the same route in the same mode, each at
  /// their own spawn on the same wall. Also the next climb after Play again.
  void _startOnline() {
    final r = online.room;
    if (r == null || (phase != Phase.menu && !onlineClimb)) return;
    _roundPlayed = online.startedRound;
    _modeBefore ??= mode;
    mode = Mode.fromName(r.mode);
    onlineClimb = true;
    _sendAcc = 0;
    _onlineStart = _netMs;
    myFinish = null;
    final wall = roomWall(r);
    spawn = roomSpawn(r, wall);
    startRoute(wall);
  }

  /// What the others need to draw your climber.
  ClimberState myState() => ClimberState(
        t: _netMs.round(),
        climber: climber.id,
        c: cd,
        tilt: tilt,
        lookX: lookX,
        lookUp: lookUp,
        ends: endDraw,
        styles: hStyle,
        kinds: hKind,
        footFree: fFree,
        falling: phase == Phase.falling,
        topped: phase == Phase.top || toppedOut,
        standing: standOn != null && drag == null,
        facingLeft: facing < 0,
        metres: climberHeight(),
        secs: onlineSecs,
      );

  /// The countdown, sending your state and moving the others. Your own
  /// climber never waits for any of this.
  void _net(double rawDt) {
    _netMs += rawDt * 1000;
    if (countdown case final left?) {
      countdown = left - rawDt;
      if (countdown! <= 0) {
        countdown = null;
        _startOnline();
      }
    }
    if (!onlineClimb) return;
    if (route != null && endDraw.length == 4 && (_sendAcc += rawDt) >= 0.1) {
      _sendAcc = math.min(_sendAcc - 0.1, 0.1);
      online.sendState(myState().encode());
    }
    remotes.update(_netMs.round(), math.min(0.1, rawDt), clock, still: reducedMotion, onEvent: _remoteEvent);
    if ((_standAcc += rawDt) >= 0.25) {
      _standAcc = 0;
      _updateStandings();
    }
  }

  /// Back from a card: to the title screen, or out of the room when online.
  void goBack() => onlineClimb ? leaveOnline() : showMenu();
  String get backLabel => onlineClimb ? 'Leave' : 'Routes';

  /// Leaves the room, closes the connection and goes back to the title screen.
  void leaveOnline() {
    online.close();
    remotes.clear();
    countdown = null;
    onlineClimb = false;
    spawn = null;
    toppedOut = false;
    _roundPlayed = 0;
    myFinish = null;
    _updateStandings();
    if (_modeBefore case final m?) {
      mode = m;
      _modeBefore = null;
    }
    if (phase == Phase.menu) {
      screen = Screen.menu;
      _ui();
    } else {
      showMenu();
    }
  }

  /// The name you play under online.
  String get playerName => store.getString('mpName') ?? '';
  set playerName(String v) => store.set('mpName', v);

  /// A new day brings a new Daily Wall, even if the app stayed open.
  void _refreshDaily() {
    if (_fixedDay != null) return;
    final now = DateTime.now(), key = dateKey(now);
    if (key == todayKey) return;
    todayKey = key;
    routes[routes.length - 1] = dailyWallFor(now);
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
    if (phase != Phase.top) return; // a second tap while the card fades out
    if (onlineClimb) return restart(); // the room climbs one route
    final i = _routeIndex(route!);
    startRoute(routes[(i + 1) % routes.length]);
  }

  // ================================================================ tips and toasts

  static final List<_Tip> _tips = [
    // the lesson's first move is from the start holds; an online spawn starts elsewhere
    _Tip('start', 'Drag your right foot up to the small step.', (g) => g.moves == 0 && g.spawn == null),
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
    if (standOn != null && social && !store.getBool('tip.walk', false)) {
      store.set('tip.walk', true);
      showTip('Hold beside your climber to walk (A and D on a keyboard). Grab a hold to climb. On a ledge you can stand and walk too.');
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
    if (phase == Phase.falling && (fall?.window ?? false)) {
      _tapCatch(pos);
      return;
    }
    if (phase != Phase.climb || _ptr != null || dyno != null || cele != null) return;
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
      // standing: a finger held beside the climber walks there
      if (standOn != null && _besideClimber(pos)) {
        _walkHold = (sy: pos.dy, at: clock);
        walkTo = s2w(pos.dx, pos.dy).x;
      }
    }
  }

  /// Is [pos] (on screen) beside the standing climber, about level with them?
  bool _besideClimber(Offset pos) {
    final w = s2w(pos.dx, pos.dy), y = holds[standOn!].y;
    return w.y > y - 60 && w.y < y + 230 && (w.x - cd.x).abs() > 22;
  }

  void pointerMove(int id, Offset pos) {
    if (id != _ptr) return;
    if (_walkHold case final wh?) {
      // a quick move up or down is a pan after all; otherwise keep walking toward the finger
      if ((pos.dy - wh.sy).abs() > 12 && clock - wh.at < 0.15) {
        _walkHold = null;
        walkTo = null;
      } else {
        walkTo = s2w(pos.dx, pos.dy).x;
        return;
      }
    }
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
    _walkHold = null;
    walkTo = null;
  }

  void recenter() {
    camManual = null;
    showRecenter = false;
    _ui();
  }

  void _beginDrag(int i, Offset pos, bool touch) {
    final l = limbs[i];
    if (standOn != null && !isHand[i]) {
      shake = Shake(i, 0.45);
      _play(Sfx.no);
      toast('Grab a hold with a hand first.', ToastKind.warn);
      return;
    }
    walkTo = null;
    _walkV = 0;
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
    final d = drag!, h = holds, r = route!, idx = r.byY;
    d.status.clear();
    // only holds within 230 of the body matter; the Daily Wall has thousands
    for (var n = r.firstAtOrAbove(c.y - 230); n < idx.length; n++) {
      final k = idx[n], hold = h[k];
      if (hold.y > c.y + 230) break;
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
      if (feasible(limbs, d.i, pt, c, climber) != null) {
        d.status[k] = q == Quality.good ? HoldStatus.good : HoldStatus.weak;
      } else {
        d.status[k] = isHand[d.i] && dynoCheck(limbs, d.i, pt, c, climber).ok ? HoldStatus.dyno : HoldStatus.far;
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
    final h = holds, r = route!, idx = r.byY;
    var best = -1;
    var bd = 30.0;
    for (var n = r.firstAtOrAbove(w.y - bd); n < idx.length; n++) {
      final k = idx[n];
      if (h[k].y > w.y + bd) break;
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
      } else if (feasible(limbs, d.i, pt, c, climber) == null) {
        final dc = dynoCheck(limbs, d.i, pt, c, climber);
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
    if (!cancelled && d.candOk && standOn != null) {
      // the first grab from standing (or a jump from it): now you climb. A
      // fall from here brings you back to where you stood: on the ground
      // until a ledge saves you, and on the ledge that saved you.
      final at = standOn!, t = holds[at].t;
      final saved = t == HoldType.ground ? (cpLedge ?? 0) == 0 : t == HoldType.ledge && mode.ledges && cpLedge == at;
      if (saved && !route!.endless) checkpoint = Checkpoint(d.snap, at);
      standOn = null;
      walkAmt = 0;
    }
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
      _grabbed(d.cand);
      final hand = isHand[d.i];
      effects.burst(l.x, l.y + (hand ? 3 : 0), hand ? PartKind.chalk : PartKind.dust, hand ? 8 : 6);
      _play(hand ? _grabSound(holds[d.cand].t) : Sfx.foot, pan: panOf(l.x));
      if (!hand) _maybeStand();
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
    standOn = s.stand;
    _walkV = walkAmt = 0;
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
    _walkHold = null;
    walkTo = null;
    _walkKeys.clear();
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

  /// Keyboard: U undo, L look, Esc pause or back, Space or Enter to try again or go on,
  /// Space while falling to catch the easiest hold in reach.
  /// -1 for a walk-left key (A, left arrow), 1 for walk right (D, right arrow), else 0.
  static int _walkKey(LogicalKeyboardKey k) => k == LogicalKeyboardKey.keyA || k == LogicalKeyboardKey.arrowLeft
      ? -1
      : (k == LogicalKeyboardKey.keyD || k == LogicalKeyboardKey.arrowRight ? 1 : 0);

  /// A key was let go (only walking cares).
  bool keyUp(LogicalKeyboardKey k) {
    final dir = _walkKey(k);
    return dir != 0 && _walkKeys.remove(dir);
  }

  bool key(LogicalKeyboardKey k, {bool ctrl = false}) {
    final f = fall;
    if (phase == Phase.falling && f != null && f.window && k == LogicalKeyboardKey.space) {
      final b = f.best;
      if (b != null) _snatch(b);
      return true;
    }
    if (phase == Phase.climb) {
      final dir = _walkKey(k);
      if (dir != 0 && social) {
        _walkKeys.add(dir);
        return true;
      }
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
    } else if (phase == Phase.fallCard && k == LogicalKeyboardKey.escape) {
      goBack();
      return true;
    } else if (phase == Phase.top && screen == Screen.topCard && k == LogicalKeyboardKey.enter) {
      nextRoute();
      return true;
    } else if (phase == Phase.top && screen == Screen.topCard && k == LogicalKeyboardKey.escape) {
      goBack();
      return true;
    } else if (phase == Phase.paused && k == LogicalKeyboardKey.escape) {
      resume();
      return true;
    } else if (screen == Screen.online && k == LogicalKeyboardKey.escape) {
      leaveOnline();
      return true;
    }
    return false;
  }

  // ================================================================ simulation

  void frame(double rawDt) {
    _net(rawDt);
    final dt = math.min(0.1, rawDt);
    // Once a card fully covers the scene, nothing behind it needs to move or
    // be drawn again (it sits under an 86% dark backdrop).
    final covered = screen == Screen.pause || screen == Screen.fallCard || screen == Screen.topCard || screen == Screen.results;
    _coveredFor = covered ? _coveredFor + dt : 0;
    if (_coveredFor > 0.5) return;
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
    if (!toppedOut) time += dt;
    if (cele != null) return;
    if (dyno != null) {
      _stepDyno(dt);
      return;
    }
    if (standOn != null && drag == null) {
      _stepStand(dt);
      return;
    }
    final anc = anchors();
    final d = drag;
    if (d != null) anc.add(Anchor(d.i, d.px, d.py, 0.22));
    final sol = solve(c, anc, 24);
    c.x = sol.x;
    c.y = sol.y;
    final g = gripRates(limbs, holds, mode, climber), s = g.s;
    for (var i = 0; i < 2; i++) {
      var r = g.rates[i];
      if (r < 0 && drag != null) r *= climber.aimSlow;
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
        _snatchHang = false;
      } else {
        hangT -= dt * (drag != null ? slowWhileAiming : 1);
        if (hangT <= 0) {
          hangT = 0;
          final hi = limbs[0].h != null ? 0 : 1, hh = limbs[hi].h;
          _startFall(
              FallInfo(
                hang: true,
                i: hi,
                t: hh != null ? holds[hh].t : HoldType.jug,
                feetW: 0,
                hands: 1,
                height: climberHeight(),
              )..afterCatch = _snatchHang,
              chance: !_snatchHang);
          return;
        }
      }
    }
    maxY = math.max(maxY, c.y);
    if (keepsRecords && !newBestShown && bestAtStart > 1 && (maxY - 100) / unitsPerMetre > bestAtStart + 0.05) {
      newBestShown = true;
      toast('New best!', ToastKind.ok);
      _play(Sfx.best);
      effects.burst(cd.x, cd.y + 50, PartKind.spark, 12);
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
    _grabbed(dy.hold);
    grip[dy.i] = math.max(1.0, grip[dy.i] - climber.catchCostFor(dy.q));
    holdTime[dy.i] = 0;
    dyno = null;
    hangT = hangMax = climber.hangTime;
    effects.burst(l.x, l.y + 3, PartKind.chalk, 14);
    camShake = math.max(camShake, 3.0);
    _play(Sfx.catchHold, pan: panOf(l.x));
    toast('Grab another hold!', ToastKind.warn);
    _ui();
  }

  void _releaseHand(int i, Support s) {
    final l = limbs[i], h = holds[l.h!];
    final info = FallInfo(hang: false, i: i, t: h.t, feetW: s.feetW, hands: s.hands, height: climberHeight());
    effects.burst(l.x, l.y, PartKind.pebble, 5);
    camShake = math.max(camShake, 3.0);
    _play(Sfx.slip, pan: panOf(l.x));
    slipFlash = 1;
    l.h = null;
    holdTime[i] = 0;
    if (drag != null && !supportInfo(limbs, holds).supported) endDrag(true);
    if (!supportInfo(limbs, holds).supported) {
      _startFall(info..afterCatch = _snatchHang, chance: !_snatchHang);
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
        effects.burst(h.x + 16, h.y + 10, PartKind.spark, 14);
        _play(Sfx.save, pan: panOf(h.x + 16));
      }
      _ui();
    } else if (h.t == HoldType.ledge) {
      toast('Resting. No saves.', ToastKind.ok);
    }
  }

  /// The body has lost its hold. If a hold is in reach on the way down (and
  /// this fall still has its one chance), time slows and the player can tap
  /// one to catch it; the fall only counts once that moment has passed.
  void _startFall(FallInfo info, {bool chance = true}) {
    if (drag != null) endDrag(true);
    dyno = null;
    hangT = 0;
    _snatchHang = false;
    _swing = null;
    info.reached = math.max(0, maxY - 100) / unitsPerMetre;
    info.prevBest = bestHeight(route!);
    _play(Sfx.fall, pan: panOf(c.x));
    final f = fall = FallState(info, trace.map((e) => [...e]).toList(), chance: chance && _catchAhead());
    for (final l in limbs) {
      l.h = null;
    }
    phase = Phase.falling;
    look = false;
    tipText = null;
    if (f.chance) {
      f.window = f.offered = true;
      _findCatches(f);
      audio.muffle(true);
      _play(Sfx.heart);
    } else {
      _fallFinal(f);
    }
    _ui();
  }

  /// The fall is for real: count it.
  void _fallFinal(FallState f) {
    if (f.counted) return;
    f.counted = true;
    commitSegment();
    if (keepsRecords) {
      records.falls++;
      records.saveLog();
    }
    falls++;
  }

  /// The catch moment passed (too fast, or the ground): the fall counts.
  void _closeCatch(FallState f) {
    if (!f.window) return;
    _endSlowMo(f);
    _fallFinal(f);
    _ui();
  }

  /// Time speeds up again and the holds stop glowing; the chance is used.
  void _endSlowMo(FallState f) {
    f.window = false;
    f.chance = false;
    f.options = const [];
    audio.muffle(false);
  }

  void _clearCatch() {
    _snatchHang = false;
    _swing = null;
    catchFlash = null;
  }

  /// Hand [i]'s grip after catching [h] at [speed], and where it would hold.
  SnatchOption? _option(int k, Hold h, int i, Pt body, double speed) {
    final pt = snatchPoint(h, i, body, climber);
    if (pt == null) return null;
    final cost = snatchCost(h.t, speed, climber);
    return SnatchOption(k, i, pt, cost, grip[i] - cost);
  }

  /// Holds near height [y0] to [y1], by height.
  Iterable<int> _holdsBetween(double y0, double y1) sync* {
    final r = route!;
    for (var n = r.firstAtOrAbove(y0); n < r.byY.length; n++) {
      final k = r.byY[n];
      if (r.holds[k].y > y1) break;
      yield k;
    }
  }

  /// Will any hold come within reach, with grip to spare, before the fall is too fast?
  bool _catchAhead() {
    for (var d = 0.0; d <= snatchDrop; d += 12) {
      final body = Pt(c.x, c.y - d);
      for (final k in _holdsBetween(body.y + 10, body.y + 130)) {
        for (var i = 0; i < 2; i++) {
          final o = _option(k, holds[k], i, body, 0);
          if (o != null && o.left > 0) return true;
        }
      }
    }
    return false;
  }

  /// The holds in reach right now; each with the hand that would keep more grip.
  void _findCatches(FallState f) {
    final out = <SnatchOption>[];
    for (final k in _holdsBetween(c.y + 10, c.y + 130)) {
      SnatchOption? pick;
      for (var i = 0; i < 2; i++) {
        final o = _option(k, holds[k], i, c, -f.v);
        if (o != null && (pick == null || o.left > pick.left)) pick = o;
      }
      if (pick != null) out.add(pick);
    }
    f.options = out;
  }

  /// A tap while falling: catch the glowing hold under the finger, if any.
  void _tapCatch(Offset pos) {
    final f = fall!;
    final at = s2w(pos.dx, pos.dy);
    SnatchOption? pick;
    var bd = math.max(34.0, 26 * scale);
    for (final o in f.options) {
      final h = holds[o.hold];
      // a ledge glows along its lip around the hand, and counts anywhere there
      final x = h.t.wide ? clampD(at.x, math.max(h.x, o.pt.x - catchLip), math.min(h.x2!, o.pt.x + catchLip)) : o.pt.x;
      final d = (w2s(x, o.pt.y) - pos).distance;
      if (d < bd) {
        bd = d;
        pick = o;
      }
    }
    if (pick != null) _snatch(pick);
  }

  /// Half the length of a ledge's lip that glows around the catching hand.
  static const double catchLip = 40;

  /// A falling hand grabs [o]. With grip to spare it holds: the body swings
  /// under it and has a moment to find a second hold. Without, the fingers
  /// brush it and slip, and the fall goes on.
  void _snatch(SnatchOption o) {
    final f = fall!, speed = -f.v;
    _endSlowMo(f);
    if (o.left <= 0) {
      effects.burst(o.pt.x, o.pt.y, PartKind.pebble, 5);
      _play(Sfx.slip, pan: panOf(o.pt.x));
      toast('Too tired to hold it', ToastKind.warn);
      _fallFinal(f);
      _ui();
      return;
    }
    final i = o.i, l = limbs[i];
    l.h = o.hold;
    l.x = o.pt.x;
    l.y = o.pt.y;
    grip[i] = math.max(1.0, grip[i] - o.cost);
    holdTime[i] = 0;
    chalked.add(o.hold);
    _grabbed(o.hold);
    // the body ends up hanging under the hand, and swings there from where it was
    final from = cd.copy(), hang = solve(c, [Anchor(i, o.pt.x, o.pt.y)], 60, climber.reach);
    c.x = hang.x;
    c.y = hang.y;
    final k = clampD(speed / snatchMaxSpeed, 0, 1);
    _swing = reducedMotion ? null : (dx: from.x - c.x, dy: from.y - c.y, dip: 3 + 4 * k, t: 0);
    if (reducedMotion) cd = c.copy();
    fall = null;
    phase = Phase.climb;
    hangT = hangMax = climber.hangTime + 0.6;
    _snatchHang = true;
    history.clear(); // no undo back into the fall
    camManual = null;
    showRecenter = false;
    if (keepsRecords) {
      records.catches++;
      records.saveLog();
    }
    store.set('tip.catch', true);
    effects.burst(o.pt.x, o.pt.y + 3, PartKind.chalk, 18);
    catchFlash = CatchFlash(o.pt.copy());
    if (!reducedMotion) camShake = math.max(camShake, 3 + 5 * k);
    slipFlash = 0;
    _play(Sfx.snatch, pan: panOf(o.pt.x));
    toast(k < 0.35 ? 'Caught it!' : (k < 0.75 ? 'Great catch!' : 'What a catch!'), ToastKind.ok);
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
    standOn = cp.snap.stand;
    _walkV = walkAmt = 0;
    cd = c.copy();
    endDraw = limbs.map((l) => Pt(l.x, l.y)).toList();
    grip = [100, 100];
    holdTime = [0, 0];
    history.clear();
    trace.clear();
    effects.parts.clear();
    cpLedge = cp.ledge;
    fall = null;
    camManual = null;
    dyno = null;
    hangT = 0;
    _clearCatch();
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
    if (f.hang && f.afterCatch) {
      why = 'You caught a hold as you fell, but you did not get a second hold in time.';
      fix = 'After a catch, put a foot on a hold right away.';
    } else if (f.hang) {
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
    // until the first catch, teach it on a fall that could have been caught
    if (note == null && fall!.offered && !store.getBool('tip.catch', false)) {
      note = 'While you fall, tap a glowing hold to catch it.';
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

  /// With others: your time stops and goes to the room for the results.
  void _reachedTop() {
    toppedOut = true;
    myFinish ??= onlineClimb ? onlineSecs : time;
    if (onlineClimb) {
      online.topped(myFinish!);
      _updateStandings();
    }
    _play(Sfx.top);
    toast('You topped out! ${fmtTime(myFinish!)}', ToastKind.ok);
    _ui();
  }

  /// With others the climb goes on at the top: the cheer, then you stand on
  /// the top and can walk all along it. No top card; the results come when
  /// the room's climb ends.
  void _topOutTogether() {
    final top = limbs[0].h!, h = holds[top], r = route!;
    if (!toppedOut) _reachedTop();
    cele = Cele(c.copy(), Pt(clampD(c.x, h.x + 30, h.x2! - 30), r.topY + standHeight(climber)));
    _celeStand = top;
    drag = null;
    for (final l in limbs) {
      l.h = null;
    }
  }

  void _topOut() {
    if (social) return _topOutTogether();
    phase = Phase.top;
    if (onlineClimb) {
      myFinish ??= onlineSecs;
      _updateStandings();
    }
    commitSegment();
    if (keepsRecords) {
      records.tops++;
      records.saveLog();
    }
    _play(Sfx.top);
    final r = route!, best = bestTime(r);
    final String note;
    final bool isBest;
    if (!keepsRecords) {
      isBest = false;
      note = 'Online climbs are not saved in your records.';
    } else if (best == null) {
      isBest = true;
      note = 'Your first time at the top!';
    } else if (time < best) {
      isBest = true;
      note = 'New best time!';
    } else {
      isBest = false;
      note = 'Best time: ${fmtTime(best)}';
    }
    if (isBest) records.newBestTime(r, mode, time: time, moves: moves, climber: climber);
    final top = holds[limbs[0].h!];
    cele = Cele(c.copy(), Pt(clampD(c.x, top.x + 30, top.x2! - 30), r.topY + standHeight(climber)));
    for (final l in limbs) {
      l.h = null;
    }
    final t = time, mv = moves, fl = falls;
    later(2.0, () {
      if (route != r || phase != Phase.top) return;
      topCard = TopCardData(
        r.name,
        t,
        mv,
        fl,
        note,
        !isBest,
        _routeIndex(r) == routes.length - 1 ? 'First route' : 'Next route',
        climber.name,
      );
      screen = Screen.topCard;
      _ui();
    });
    _ui();
  }

  // ================================================================ animation

  void _animate(double rawDt) {
    clock += rawDt;
    // while a falling climber can catch a hold, the world runs slow (UI time does not)
    final dt = rawDt * (fall?.slow ?? 1);
    effects.update(dt, clock);
    curtain = math.max(0.0, curtain - dt / 0.45);
    slipFlash = math.max(0.0, slipFlash - dt * 1.4);
    camShake = math.max(0.0, camShake - dt * 18);
    br = reducedMotion
        ? 0.0
        : math.sin(clock * ((grip[0] < 40 || grip[1] < 40) && phase == Phase.climb ? 4.4 : 2.1));
    if (phase == Phase.menu) {
      scale = baseScale();
      camX = 180;
      camY = menuRoute.topY - 0.11 * ch / scale;
      lookX = -2.2 + math.sin(clock * 0.3) * 0.5;
      _menuHop += dt;
      final u = _menuHop / 0.42;
      _placeMenuClimber(u < 1 && !reducedMotion ? math.sin(u * math.pi) * 15 : 0);
      if (u >= 1 && !_menuLanded) {
        _menuLanded = true;
        effects.burst(cd.x, menuRoute.topY + 2, PartKind.dust, 8);
        _play(Sfx.foot, pan: panOf(cd.x));
      }
      pose = buildPose();
      if (gear == null) _gearInit();
      _gearUpdate(dt);
      audio.setWind(0.05);
      return;
    }
    final r = route;
    if (r == null) return;
    drag?.age += dt;
    lookK += ((look ? 1 : 0) - lookK) * math.min(1.0, dt * (reducedMotion ? 30 : 7));
    final f = fall;
    final ce = cele;
    if (phase == Phase.falling && f != null) {
      // ease into slow motion while a hold can be caught, and back out after
      final want = f.window ? mode.slowMo : 1.0;
      f.slow += (want - f.slow) * math.min(1.0, rawDt / (f.window ? 0.12 : 0.25));
      f.t += dt;
      f.v -= fallGravity * dt;
      c.y += f.v * dt;
      if (c.y < 64) {
        c.y = 64;
        if (!f.landed) {
          f.landed = true;
          camShake = 7;
          effects.burst(c.x, 4, PartKind.dust, 16);
          _play(Sfx.land, pan: panOf(c.x));
        }
        f.v = 0;
      }
      cd.x = c.x;
      cd.y = c.y;
      if (f.window) {
        _findCatches(f);
        if (-f.v > snatchMaxSpeed || f.landed) _closeCatch(f);
      }
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
          later(n * 0.14, () => effects.burst(cd.x + (_rand.nextDouble() - 0.5) * 60, cd.y + 60 + _rand.nextDouble() * 30, PartKind.spark, 12));
        }
      }
      final top = _celeStand;
      if (ce.t > 1.1 && top != null) {
        // with others: the cheer is over, now stand on the top
        cele = null;
        _celeStand = null;
        _standOn(top, c.x);
        resetPoseState([HandStyle.open, HandStyle.open]);
      }
    } else if (_swing case final sw?) {
      // swinging under the hand that caught the fall, then settling
      final t = sw.t + dt;
      _swing = t > 2.2 ? null : (dx: sw.dx, dy: sw.dy, dip: sw.dip, t: t);
      cd.x = c.x + sw.dx * math.exp(-t / 0.45) * math.cos(t * 9);
      cd.y = c.y + sw.dy * math.exp(-t / 0.08) - sw.dip * math.exp(-t / 0.22) * math.sin(t * 14);
    } else {
      final k = math.min(1.0, dt * 18);
      cd.x += (c.x - cd.x) * k;
      cd.y += (c.y - cd.y) * k;
    }
    final cf = catchFlash;
    if (cf != null && (cf.t += dt) > 0.4) catchFlash = null;
    scale = lerpD(baseScale(), lookScale(), lookK);
    if (drag == null) {
      final normY = camManual ?? cd.y + 40, normX = camXFor(cd.x);
      final lookY = r.endless ? cd.y + 320 : (r.topY + 50) / 2;
      // Look shows the lane you are in now
      final ty = lerpD(normY, lookY, lookK), tx = lerpD(normX, r.laneAt(cd.x).mid, lookK), e = reducedMotion ? 1.0 : math.min(1.0, dt * 6);
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
    if (phase == Phase.climb && low < 25) audio.breath((25 - low) / 25, clock);
    if (r.endless && cd.y > snowY - 400 && !reducedMotion) {
      final v = viewRange();
      effects.snow(dt, v.x0, v.x1, v.y1);
    }
    _limbTargets(dt);
    // body lean: hands over feet
    final e = endDraw;
    final tl = standOn != null && drag == null
        ? facing * 0.03 * walkAmt
        : clampD(((e[2].x + e[3].x) - (e[0].x + e[1].x)) * 0.5 * 0.0035, -0.16, 0.16) +
        (phase == Phase.falling && !reducedMotion ? math.sin((fall?.t ?? 0) * 7 + 1) * 0.25 : 0);
    tilt += (tl - tilt) * math.min(1.0, dt * 8);
    // where the head looks
    Pt? tgt;
    if (drag != null) {
      tgt = Pt(drag!.px, drag!.py);
    } else if (dyno != null) {
      tgt = dyno!.pt;
    } else if (fall?.best case final b?) {
      tgt = b.pt;
    } else if (cele != null) {
      tgt = Pt(cd.x - 120, cd.y + 160);
    }
    final hx = cd.x, hy = cd.y + 38;
    final lkX = tgt != null
        ? clampD((tgt.x - hx) * 0.045, -3, 3)
        : (standOn != null && walkAmt > 0.05 ? facing * 2.2 : math.sin(clock * 0.35) * 1.2);
    final lkUp = tgt != null ? clampD((tgt.y - hy) * 0.008, -0.6, 1) : 0.5;
    lookX += (lkX - lookX) * math.min(1.0, dt * 6);
    lookUp += (lkUp - lookUp) * math.min(1.0, dt * 6);
    pose = buildPose();
    _gearUpdate(dt);
  }

  void _limbTargets(double dt) {
    if (limbs.length != 4) return;
    final ph = phase, bag = gear?.bag, r = route!;
    final at = standOn;
    final sp = at != null && ph == Phase.climb
        ? standAt(climber, cd.x, holds[at].y, facing: facing, phase: walkPhase, walk: walkAmt)
        : null;
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
        (tx, ty) = _toward(i, j, dy.pt);
      } else if (d != null && d.i == i) {
        (tx, ty) = _toward(i, j, d.candOk ? d.candPt! : Pt(d.px, d.py));
      } else if (sp != null) {
        // standing: feet step along the hold, hands hang loose
        tx = sp.ends[i].x;
        ty = sp.ends[i].y;
        snap = true;
        free = !hand && ty > holds[standOn!].y + 0.5;
      } else if (l.h != null) {
        tx = l.x;
        ty = l.y;
        snap = true;
        if (hand) {
          style = HandStyle.grip;
          hKind[i] = holds[l.h!].t;
        }
      } else if (ph == Phase.falling) {
        final o = hand ? _reachFor(i) : null;
        if (o != null) {
          (tx, ty) = _toward(i, j, o.pt); // reaching for a hold, fingers open
        } else {
          tx = j.x + sideOf[i] * (hand ? 26 : 16);
          ty = j.y + (hand ? 38 : -52);
        }
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
          effects.burst(tx, ty, PartKind.chalk, 6);
          // A puff on every dip, but the sound only now and then.
          if (clock - lastChalkSound > 6) {
            lastChalkSound = clock;
            _play(Sfx.chalk, pan: panOf(tx));
          }
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

  /// Where limb [i] from joint [j] gets toward [target], as far as it reaches.
  (double, double) _toward(int i, Pt j, Pt target) {
    final dx = target.x - j.x, dy = target.y - j.y;
    var len = hypot(dx, dy);
    if (len == 0) len = 1;
    final m = math.min(1.0, (climber.reach[i] + 2) / len);
    return (j.x + dx * m, j.y + dy * m);
  }

  /// The hold falling hand [i] reaches for: its easiest catch, if any.
  SnatchOption? _reachFor(int i) {
    SnatchOption? b;
    for (final o in fall?.options ?? const <SnatchOption>[]) {
      if (o.i == i && (b == null || o.left > b.left)) b = o;
    }
    return b;
  }

  // ================================================================ pose

  /// The hand at the end of arm [i], shaking a little when it is very tired.
  Pt _handEnd(int i) {
    final e0 = endDraw[i].copy();
    if (hStyle[i] == HandStyle.grip && grip[i] < 35 && !reducedMotion && phase == Phase.climb) {
      final amp = (35 - grip[i]) / 35 * 1.6;
      e0.x += math.sin(clock * 47 + i) * amp;
      e0.y += math.cos(clock * 39 + i * 2) * amp * 0.5;
    }
    if (shake != null && shake!.i == i && !reducedMotion) e0.x += math.sin(clock * 60) * 3;
    return e0;
  }

  Pose buildPose() => climberPose(
        climber,
        cd.copy(),
        tilt,
        br,
        lookX,
        lookUp,
        [_handEnd(0), _handEnd(1)],
        hStyle,
        hKind,
        [endDraw[2], endDraw[3]],
        fFree,
        [for (final i in [2, 3]) tremble > 0 && !reducedMotion ? math.sin(clock * 41 + i * 1.7) * tremble : 0.0],
      );

  void _gearInit() {
    final p = pose = buildPose();
    gear = Gear(p, links: outfit.tailLinks, link: outfit.tailLink);
  }

  void _gearUpdate(double dt) {
    if (gear == null) _gearInit();
    final windy = phase == Phase.menu || cele != null;
    final wind = (windy ? 360.0 : 25.0) * (0.6 + 0.4 * math.sin(clock * 0.9)) + (windy ? 90 * math.sin(clock * 3.1) : 0.0);
    gear!.update(pose!, dt, wind);
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
    final seen = <double>{};
    for (var k = 0; k < r.holds.length; k++) {
      final h = r.holds[k];
      // one mark per height: every lane has the same ledges
      if (h.t != HoldType.ledge || !seen.add(h.y)) continue;
      final m = (h.y - 100) / unitsPerMetre;
      if (m > span) continue;
      ticks.add(Tick(m / span, k));
    }
  }

  /// A ledge mark is lit when a ledge at its height is lit, in any lane.
  bool tickLit(Tick t) {
    final y = holds[t.hold].y;
    return lit.any((k) => holds[k].y == y);
  }

  /// Keeps the ledge marks on the progress bar in step with the Daily Wall.
  void refreshTicks() {
    if (route == null) return;
    final span = progSpan();
    if (_tickRoute != route || (span - _tickSpan).abs() > 0.5) _buildTicks();
  }

  String get pillText {
    if (phase == Phase.climb && hangT > 0) return 'Grab a hold!';
    if (phase == Phase.climb && toppedOut && myFinish != null) return 'Topped out · ${fmtTime(myFinish!)}';
    if (phase == Phase.climb && route != null && supportInfo(limbs, holds).standing && c.y > 120) return 'Resting';
    return '';
  }
}
