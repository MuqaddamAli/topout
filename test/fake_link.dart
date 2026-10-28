// A fake room server for tests: it records what the game sends and answers
// with whatever the test sets.
import 'package:flutter/foundation.dart';
import 'package:topout/game/online.dart';

/// Stands in for the server: records what the game sends and answers asks.
class FakeLink implements NetLink {
  VoidCallback? up, down;
  bool closed = false;
  final Map<String, void Function(Object?)> handlers = {};
  final List<(String, Object?)> sent = [];
  Object? Function(String event, Object? data) answer = (_, __) => const <String, Object?>{};

  @override
  void open({required VoidCallback onUp, required VoidCallback onDown}) {
    up = onUp;
    down = onDown;
  }

  @override
  void close() => closed = true;

  @override
  void emit(String event, [Object? data]) => sent.add((event, data));

  @override
  Future<Object?> ask(String event, [Object? data]) {
    sent.add((event, data));
    return Future.value(answer(event, data));
  }

  @override
  void listen(String event, void Function(Object? data) handler) => handlers[event] = handler;

  void push(String event, Object? data) => handlers[event]?.call(data);
  Object? last(String event) => sent.lastWhere((s) => s.$1 == event).$2;
  bool did(String event) => sent.any((s) => s.$1 == event);
}

Map<String, Object?> roomJson({String host = 'me', List<String> names = const ['Ada'], bool started = false}) => {
      'code': 'KXMP',
      'route': 'first',
      'mode': 'normal',
      'dateKey': '2026-10-28',
      'host': host,
      'started': started,
      'max': 8,
      'players': [
        for (var k = 0; k < names.length; k++)
          {'id': k == 0 ? host : 'p$k', 'name': names[k], 'climber': 'ada', 'connected': true},
      ],
    };

/// What the server answers to a create or join.
Map<String, Object?> entered(Map<String, Object?> room, {String you = 'me'}) =>
    {'you': you, 'token': 't', 'room': room, 'startsIn': null};
