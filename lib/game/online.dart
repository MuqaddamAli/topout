// Online play: the connection to the room server (server/ in this repo), the
// room you are in and who else is there. The server is set at build time
// with --dart-define=MP_SERVER=https://...; nothing connects until you open
// Play online.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

const String mpServer = String.fromEnvironment('MP_SERVER', defaultValue: 'http://localhost:3000');

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

  @override
  void emit(String event, [Object? data]) => _s?.emit(event, data);

  @override
  Future<Object?> ask(String event, [Object? data]) {
    final s = _s, done = Completer<Object?>();
    if (s == null) return Future.value(const {'error': 'Not connected'});
    s.emitWithAck(event, data, ack: (Object? r) {
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
  RoomPlayer({required this.id, required this.name, required this.climber, required this.connected});
  final String id, name, climber;
  final bool connected;

  factory RoomPlayer.fromJson(Map m) => RoomPlayer(
        id: '${m['id']}',
        name: '${m['name']}',
        climber: '${m['climber']}',
        connected: m['connected'] != false,
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
  });
  final String code, route, mode, dateKey, host;
  final bool started;
  final int max;
  final List<RoomPlayer> players;

  factory RoomView.fromJson(Map m) => RoomView(
        code: '${m['code']}',
        route: '${m['route']}',
        mode: '${m['mode']}',
        dateKey: '${m['dateKey']}',
        host: '${m['host']}',
        started: m['started'] == true,
        max: (m['max'] as num?)?.toInt() ?? 8,
        players: [for (final p in (m['players'] as List? ?? const [])) RoomPlayer.fromJson(p as Map)],
      );

  RoomPlayer? player(String? id) => players.where((p) => p.id == id).firstOrNull;
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
      _started(d is Map ? d['startsIn'] : null);
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

  void _started(Object? startsIn) {
    final ms = startsIn is num ? startsIn.toInt() : 0;
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
        error = 'You were away too long and lost your place in the room.';
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
