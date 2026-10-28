// Online play: the connection to the room server (server/ in this repo), the
// room you are in and who else is there. Nothing connects until you open
// Play online.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import 'core.dart';

/// The online room server (on Render).
const String onlineServer = 'https://topout.onrender.com';

/// The room server: --dart-define=MP_SERVER=... when the build sets it.
/// Otherwise, in a browser on this PC or the local network, port 3000 of the
/// same machine (for testing), and everywhere else [onlineServer].
final String mpServer =
    serverFor(const String.fromEnvironment('MP_SERVER'), kIsWeb ? Uri.base : null, debug: kDebugMode);

String serverFor(String define, Uri? page, {bool debug = false}) {
  if (define.isNotEmpty) return define.endsWith('/') ? define.substring(0, define.length - 1) : define;
  final h = page?.host;
  // an app on a phone or a desktop: the online server, or this PC while developing
  if (h == null) return debug ? 'http://localhost:3000' : onlineServer;
  final local = h == 'localhost' ||
      RegExp(r'^(10|127)\.\d+\.\d+\.\d+$').hasMatch(h) ||
      RegExp(r'^192\.168\.\d+\.\d+$').hasMatch(h) ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.\d+\.\d+$').hasMatch(h);
  return local ? 'http://$h:3000' : onlineServer;
}

enum NetStatus { off, connecting, online, failed }

/// The connection to the server, kept small so tests can use a fake one.
abstract class NetLink {
  /// [onUp] runs on every (re)connect, [onDown] when the connection drops.
  void open({required VoidCallback onUp, required VoidCallback onDown});
  void close();
  void emit(String event, [Object? data]);

  /// Sends [event] and waits for the server's answer.
  Future<Object?> ask(String event, [Object? data]);
  void listen(String event, void Function(Object? data) handler);
}

/// The real connection: Socket.io over a websocket only (no long polling).
/// The site's cross-origin isolation headers do not block websockets.
class SocketLink implements NetLink {
  SocketLink(this.url);
  final String url;
  sio.Socket? _s;

  /// Listeners added before [open] are attached when the socket is made.
  final Map<String, void Function(Object? data)> _handlers = {};

  @override
  void open({required VoidCallback onUp, required VoidCallback onDown}) {
    final s = _s = sio.io(
      url,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(4000)
          .build(),
    );
    _handlers.forEach(s.on);
    s.onConnect((_) => onUp());
    s.onDisconnect((_) => onDown());
    s.connect();
  }

  @override
  void close() {
    _s?.dispose();
    _s = null;
  }

  /// The client sends each item of a list as its own argument, so a list
  /// (a climber state) is wrapped to arrive as one.
  static Object? payload(Object? data) => data is List ? [data] : data;

  @override
  void emit(String event, [Object? data]) => _s?.emit(event, payload(data));

  @override
  Future<Object?> ask(String event, [Object? data]) {
    final s = _s, done = Completer<Object?>();
    if (s == null) return Future.value(const {'error': 'Not connected'});
    s.emitWithAck(event, payload(data), ack: (Object? r) {
      if (!done.isCompleted) done.complete(r);
    });
    return done.future.timeout(const Duration(seconds: 10), onTimeout: () => const {'error': 'The server did not answer. Try again.'});
  }

  @override
  void listen(String event, void Function(Object? data) handler) {
    _handlers[event] = handler;
    _s?.on(event, handler);
  }
}

class RoomPlayer {
  RoomPlayer(
      {required this.id, required this.name, required this.climber, required this.connected, this.lane, this.side, this.finish});
  final String id, name, climber;
  final bool connected;

  /// From the start: the lane (0 is the first) and the side in it (0 left, 1 right).
  final int? lane, side;

  /// Seconds from the start to this player's top-out, this round.
  final double? finish;

  factory RoomPlayer.fromJson(Map m) => RoomPlayer(
        id: '${m['id']}',
        name: '${m['name']}',
        climber: '${m['climber']}',
        connected: m['connected'] != false,
        lane: (m['lane'] as num?)?.toInt(),
        side: (m['side'] as num?)?.toInt(),
        finish: (m['finish'] as num?)?.toDouble(),
      );
}

/// A room as the server sends it.
class RoomView {
  RoomView({
    required this.code,
    required this.route,
    required this.mode,
    required this.dateKey,
    required this.host,
    required this.started,
    required this.max,
    required this.players,
    this.lanes,
    this.ended = false,
    this.round = 0,
  });
  final String code, route, mode, dateKey, host;
  final bool started;

  /// The climb is over (everyone topped out, or the creator ended it): the
  /// results show. [round] counts the climbs (Play again starts the next).
  final bool ended;
  final int round;
  final int max;

  /// From the start: how many lanes the wall has. It stays so when someone leaves.
  final int? lanes;
  final List<RoomPlayer> players;

  factory RoomView.fromJson(Map m) => RoomView(
        code: '${m['code']}',
        route: '${m['route']}',
        mode: '${m['mode']}',
        dateKey: '${m['dateKey']}',
        host: '${m['host']}',
        started: m['started'] == true,
        max: (m['max'] as num?)?.toInt() ?? 8,
        lanes: (m['lanes'] as num?)?.toInt(),
        ended: m['ended'] == true,
        round: (m['round'] as num?)?.toInt() ?? 0,
        players: [for (final p in (m['players'] as List? ?? const [])) RoomPlayer.fromJson(p as Map)],
      );

  RoomPlayer? player(String? id) => players.where((p) => p.id == id).firstOrNull;

  /// How many lanes the wall has: fixed by the server at the start, and
  /// before it, how many the players in the room now would get.
  int get laneCount => lanes ?? lanesFor(players.length);

  /// The lane (0 is the first) and side (0 left, 1 right) of [p]: the
  /// server's from the start; before it (or from an older server), by the
  /// order they joined, the way the server gives them.
  ({int lane, int side}) slot(RoomPlayer p) {
    final k = math.max(0, players.indexOf(p));
    return (lane: math.min(p.lane ?? k ~/ 2, laneCount - 1), side: p.side ?? k % 2);
  }
}

/// Room codes are four letters, never I, L or O.
String cleanRoomCode(String s) => s.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');

class Online extends ChangeNotifier {
  Online(this._makeLink);
  final NetLink Function() _makeLink;

  /// How long to wait for the server before giving up: a free server that
  /// has gone to sleep takes up to a minute to wake.
  static const Duration giveUpAfter = Duration(seconds: 60);

  /// When "Connecting to server…" adds that the server may be waking up.
  static const Duration slowAfter = Duration(seconds: 4);

  NetLink? _link;
  NetStatus status = NetStatus.off;

  /// Connecting has taken a while (the server is probably waking up).
  bool slow = false;
  Timer? _giveUp, _slowTimer;

  RoomView? room;
  String? you;
  String? _token;

  /// The last thing that went wrong, to show under the form.
  String? error;

  /// A create, join or start is on its way.
  bool busy = false;

  /// Set when the host starts the climb: when it begins here.
  DateTime? startsAt;

  /// The start signal, as ms from when it came in, and how many have come
  /// in (so the game can tell a new one).
  int? startsInMs;
  int starts = 0;

  /// Which climb of the room the last start was for (1, then 2 after Play again...).
  int startedRound = 0;

  /// Called with a player id and their climber state.
  void Function(String id, Object? state)? onState;

  bool get isHost => room != null && room!.host == you;
  bool get inRoom => room != null;

  void connect() {
    if (status == NetStatus.connecting || status == NetStatus.online) return;
    error = null;
    final link = _link = _makeLink();
    link.listen('room', (d) {
      if (d is! Map) return;
      room = RoomView.fromJson(d);
      notifyListeners();
    });
    link.listen('state', (d) {
      if (d is List && d.length == 2 && d[0] is String) onState?.call(d[0] as String, d[1]);
    });
    link.listen('started', (d) {
      _started(d is Map ? d['startsIn'] : null, d is Map ? d['round'] : null);
      notifyListeners();
    });
    link.open(onUp: _up, onDown: _down);
    _waiting();
  }

  /// Shows "Connecting…" and gives up after [giveUpAfter].
  void _waiting() {
    status = NetStatus.connecting;
    slow = false;
    _giveUp?.cancel();
    _slowTimer?.cancel();
    _slowTimer = Timer(slowAfter, () {
      slow = true;
      notifyListeners();
    });
    _giveUp = Timer(giveUpAfter, () {
      _stopTimers();
      _link?.close();
      _link = null;
      status = NetStatus.failed;
      if (room != null) {
        room = null;
        error = 'Lost the connection to the room.';
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void _stopTimers() {
    _giveUp?.cancel();
    _slowTimer?.cancel();
    _giveUp = _slowTimer = null;
  }

  void _up() {
    _stopTimers();
    status = NetStatus.online;
    slow = false;
    final r = room, token = _token;
    // back after a short drop: take the same place in the room again
    if (r != null && token != null) _enter(_link!.ask('rejoin', {'code': r.code, 'token': token}), lost: true);
    notifyListeners();
  }

  void _down() {
    if (status == NetStatus.off || status == NetStatus.failed) return;
    _waiting();
  }

  void retry() {
    close();
    connect();
  }

  void _started(Object? startsIn, [Object? round]) {
    final ms = startsIn is num ? startsIn.toInt() : 0;
    startedRound = round is num ? round.toInt() : (room?.round ?? 0);
    startsAt = DateTime.now().add(Duration(milliseconds: ms));
    startsInMs = ms;
    starts++;
  }

  /// Handles the answer to create, join or rejoin.
  Future<void> _enter(Future<Object?> answer, {bool lost = false}) async {
    busy = true;
    error = null;
    notifyListeners();
    final r = await answer;
    busy = false;
    if (r is Map && r['room'] is Map) {
      room = RoomView.fromJson(r['room'] as Map);
      you = '${r['you']}';
      _token = '${r['token']}';
      // a rejoin after the start is already climbing: no new start for it
      if (room!.started && !lost) _started(r['startsIn']);
    } else {
      final e = r is Map ? r['error'] : null;
      if (lost) {
        room = null;
        error = 'You lost your place in the room (it may have closed).';
      } else {
        error = e is String ? e : 'Something went wrong. Try again.';
      }
    }
    notifyListeners();
  }

  Future<void> create({
    required String name,
    required String route,
    required String mode,
    required String dateKey,
    required String climber,
  }) async {
    final link = _link;
    if (link == null || status != NetStatus.online || busy) return;
    await _enter(link.ask('create', {'name': name, 'route': route, 'mode': mode, 'dateKey': dateKey, 'climber': climber}));
  }

  Future<void> join({required String code, required String name, required String climber}) async {
    final link = _link;
    if (link == null || status != NetStatus.online || busy) return;
    if (cleanRoomCode(code).length != 4) {
      error = 'A room code has 4 letters';
      notifyListeners();
      return;
    }
    await _enter(link.ask('join', {'code': cleanRoomCode(code), 'name': name, 'climber': climber}));
  }

  void pick(String climber) {
    if (room != null) _link?.emit('pick', climber);
  }

  Future<void> start() async {
    final link = _link;
    if (link == null || !isHost || busy) return;
    busy = true;
    notifyListeners();
    final r = await link.ask('start');
    busy = false;
    final e = r is Map ? r['error'] : null;
    if (e is String) error = e;
    notifyListeners();
  }

  /// Tells the room you reached the top, [secs] after the start.
  void topped(double secs) {
    if (room != null && room!.started) _link?.emit('topped', secs);
  }

  /// The creator ends the climb for everyone (the results show), or after
  /// the results starts the next climb.
  Future<void> endClimb() => _hostAsk('end');
  Future<void> again() => _hostAsk('again');

  Future<void> _hostAsk(String event) async {
    final link = _link;
    if (link == null || !isHost || busy) return;
    busy = true;
    notifyListeners();
    final r = await link.ask(event);
    busy = false;
    final e = r is Map ? r['error'] : null;
    if (e is String) error = e;
    notifyListeners();
  }

  /// Sends your climber's state to the others (only while climbing).
  void sendState(List<Object> state) {
    if (status == NetStatus.online && room != null && room!.started) _link?.emit('state', state);
  }

  /// Leaves the room (the connection stays open).
  void leave() {
    if (room != null) _link?.emit('leave');
    room = null;
    you = _token = null;
    startsAt = null;
    startsInMs = null;
    error = null;
    notifyListeners();
  }

  /// Leaves the room and closes the connection.
  void close() {
    leave();
    _stopTimers();
    _link?.close();
    _link = null;
    status = NetStatus.off;
    busy = false;
    notifyListeners();
  }
}
