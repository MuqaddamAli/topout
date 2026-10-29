import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/audio.dart';
import '../game/core.dart';
import '../game/field_book.dart';
import '../game/game.dart';
import '../game/online.dart';
import '../game/palette.dart';
import 'climbers.dart';
import 'hud.dart' show FrameSelect, GameToast;
import 'kit.dart';
import 'motion.dart';
import 'widgets.dart';

/// Play online: make a room or join one with its code, then the lobby with
/// everyone in the room until the creator starts the climb. It is a page of
/// the field book: the room code on a big luggage tag, the players as rows
/// of a register with a pencil tick for Ready.
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key, required this.game});
  final Game game;

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  late final TextEditingController _name = TextEditingController(text: game.playerName);
  final TextEditingController _code = TextEditingController();
  late String _route = game.routes.first.id;
  late Mode _mode = game.mode;
  bool _copied = false;
  Timer? _copiedTimer;

  Game get game => widget.game;
  Online get online => game.online;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  void _tap(VoidCallback f) {
    game.audio.play(Sfx.tap);
    f();
  }

  String get _cleanName => _name.text.trim();

  void _create() => online.create(
        name: _cleanName,
        route: _route,
        mode: _mode.name,
        dateKey: game.todayKey,
        climber: game.climber.id,
      );

  void _join() => online.join(code: _code.text, name: _cleanName, climber: game.climber.id);

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [rgba(6, 9, 22, 0), rgba(6, 9, 22, 0.82), rgba(6, 9, 22, 0.92)],
                stops: const [0, 0.3, 0.5],
              ),
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: ListenableBuilder(
          listenable: online,
          builder: (context, _) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(math.max(16, pad.left), pad.top + 16, math.max(16, pad.right), pad.bottom + 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    GameButton(
                      label: online.inRoom ? 'Leave' : 'Back',
                      icon: Icons.arrow_back_rounded,
                      onTap: () => _tap(game.leaveOnline),
                    ),
                    const Spacer(),
                    _NetChip(status: online.status),
                  ]),
                  SizedBox(height: math.min(size.height * 0.12, 100)),
                  Stagger(
                    index: 0,
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'PLAY '),
                        TextSpan(text: 'ONLINE', style: TextStyle(color: Kit.webbing)),
                      ]),
                      style: FbTxt.label(64, color: Kit.blazeWhite),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Stagger(
                    index: 1,
                    child: Text('Climb the same wall with up to 8 friends, each on their own device.',
                        style: Txt.body(16, color: Kit.blazeWhite.withValues(alpha: 0.8), height: 1.4)),
                  ),
                  const SizedBox(height: 18),
                  if (online.status != NetStatus.online) ...[
                    _Connecting(online: online, onRetry: () => _tap(online.retry)),
                    const SizedBox(height: 14),
                  ],
                  Stagger(index: 2, child: online.room == null ? _entry() : _lobby(online.room!)),
                ]),
              ),
            ),
          ),
        ),
      ),
      // who joined or left the lobby
      Positioned(
        left: 14,
        right: 14,
        bottom: pad.bottom + 24,
        child: IgnorePointer(
          child: FrameSelect(
            game: game,
            select: (g) => g.toastVisible ? (g.toastText ?? '', g.toastKind, g.toastUntil) : null,
            builder: (context, t) => Center(child: GameToast(toast: t)),
          ),
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- create or join

  Widget _entry() {
    final ready = online.status == NetStatus.online && !online.busy && _cleanName.isNotEmpty;
    return FieldPage(
      angle: -0.8,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionHead(number: 1, title: 'Your name'),
        const SizedBox(height: 6),
        _Field(
          controller: _name,
          hint: 'Name others will see',
          maxLength: 16,
          onChanged: (v) => setState(() => game.playerName = v.trim()),
        ),
        const SizedBox(height: 22),
        const SectionHead(number: 2, title: 'Make a room'),
        const SizedBox(height: 8),
        Text('ROUTE', style: FbTxt.typed(12, bold: true)),
        _Pairs(children: [
          for (final r in game.routes)
            GameChoice(label: r.name, on: _route == r.id, onTap: () => _tap(() => setState(() => _route = r.id))),
        ]),
        const SizedBox(height: 6),
        Text('MODE', style: FbTxt.typed(12, bold: true)),
        Row(children: [
          for (final m in Mode.values) ...[
            if (m != Mode.values.first) const SizedBox(width: 4),
            Expanded(child: GameChoice(label: m.label, on: _mode == m, onTap: () => _tap(() => setState(() => _mode = m)))),
          ],
        ]),
        const SizedBox(height: 12),
        GameButton(label: 'Create', primary: true, onTap: ready ? () => _tap(_create) : null),
        const SizedBox(height: 22),
        const SectionHead(number: 3, title: 'Join a room'),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: _Field(
              controller: _code,
              hint: 'CODE',
              code: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: ready ? (_) => _join() : null,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: GameButton(
              label: 'Join',
              primary: true,
              onTap: ready && cleanRoomCode(_code.text).length == 4 ? () => _tap(_join) : null,
            ),
          ),
        ]),
        if (online.error case final e?) ...[const SizedBox(height: 14), _ErrorLine(e)],
      ]),
    );
  }

  // ---------------------------------------------------------------- lobby

  Widget _lobby(RoomView room) {
    final route = game.routes.where((r) => r.id == room.route).firstOrNull;
    final daily = route?.endless ?? false;
    final host = room.player(room.host);
    final facts = [route?.name ?? room.route, Mode.fromName(room.mode).label, if (daily) room.dateKey].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // the room code, on a big luggage tag
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CodeTag(code: room.code),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 18),
            Text('Send this code to your friends so they can join.', style: Txt.body(15, color: Kit.blazeWhite, height: 1.35)),
            const SizedBox(height: 6),
            Text(facts, style: FbTxt.typed(13, bold: true, color: Kit.blazeWhite)),
            const SizedBox(height: 4),
            GameButton(
              label: _copied ? 'Copied' : 'Copy',
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              onTap: () => _tap(() => _copy(room.code)),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 18),
      FieldPage(
        angle: 0.6,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            const Expanded(child: SectionHead(number: 1, title: 'Players')),
            Text('${room.players.length}/${room.max} players', style: FbTxt.typed(14, bold: true)),
          ]),
          const SizedBox(height: 2),
          Text(
              room.laneCount == 1
                  ? 'One lane: two climbers side by side.'
                  : '${room.laneCount} lanes side by side, two climbers in each. Bridges join them.',
              style: Txt.body(13, color: Kit.graphite)),
          const SizedBox(height: 6),
          // someone who joins slides into the register
          for (final p in room.players)
            KeyedSubtree(
              key: ValueKey(p.id),
              child: Once(
                duration: const Duration(milliseconds: 380),
                builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset((1 - t) * 28, 0), child: child)),
                child: _PlayerRow(player: p, lane: room.slot(p), you: p.id == online.you, host: p.id == room.host),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 22),
      Text('YOUR CLIMBER', style: FbTxt.typed(13, bold: true, color: Kit.blazeWhite)),
      const SizedBox(height: 10),
      ClimberPicker(game: game),
      const SizedBox(height: 18),
      if (online.error case final e?) ...[_ErrorLine(e), const SizedBox(height: 12)],
      if (!room.started) ...[
        Semantics(
          toggled: online.ready,
          child: GameButton(
            label: online.ready ? 'Ready ✓' : "I'm ready",
            on: online.ready,
            onTap: online.status == NetStatus.online ? () => _tap(() => online.setReady(!online.ready)) : null,
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (room.started)
        FrameSelect<int>(
          game: game,
          select: (g) => (g.countdown ?? 0).ceil(),
          builder: (context, left) => Once(
            replay: left,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutBack,
            builder: (context, t, child) => Transform.scale(scale: 1.25 - 0.25 * t, child: child),
            child: Text(left > 0 ? 'Starting in $left' : 'Starting…', textAlign: TextAlign.center, style: FbTxt.label(32, color: Kit.blazeWhite)),
          ),
        )
      else if (online.isHost)
        GameButton(
          // the creator can start any time, and sees how many are ready
          label: 'Start · ${room.players.where((p) => p.ready).length}/${room.players.length} ready',
          primary: true,
          onTap: online.status == NetStatus.online && !online.busy ? () => _tap(online.start) : null,
        )
      else
        Text('Waiting for ${host?.name ?? 'the creator'} to start…',
            textAlign: TextAlign.center, style: Txt.body(16, color: Kit.blazeWhite.withValues(alpha: 0.8))),
    ]);
  }
}

/// The room's code, big on a luggage tag on a string.
class _CodeTag extends StatelessWidget {
  const _CodeTag({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: 83, top: -30, width: 1.5, height: 46, child: ColoredBox(color: Kit.blazeWhite.withValues(alpha: 0.85))),
        // it swings in on its string
        Swing(
          swingIn: true,
          seed: code.hashCode,
          child: Transform.rotate(
            angle: -0.04,
            child: CustomPaint(
              painter: _BigTagPainter(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 34, 10, 14),
                child: Column(children: [
                  Text('ROOM', style: FbTxt.typed(12, bold: true, color: Kit.ink)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SelectableText(code, maxLines: 1, semanticsLabel: code.split('').join(' '), style: FbTxt.label(60, color: Kit.ink, spacing: 0.04)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _BigTagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = tagPath(size);
    canvas.drawPath(p.shift(const Offset(0, 6)), Paint()..color = rgba(0, 0, 0, 0.3));
    canvas.drawPath(p, Paint()..color = Kit.paper);
    final c = Offset(size.width / 2, 16);
    canvas.drawCircle(c, 8, Paint()..color = hex(0xB8AE98));
    canvas.drawCircle(c, 4.5, Paint()..color = hex(0x2A2E38));
  }

  @override
  bool shouldRepaint(covariant _BigTagPainter oldDelegate) => false;
}

/// Lays children out two in a row.
class _Pairs extends StatelessWidget {
  const _Pairs({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var i = 0; i < children.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 6),
        Row(children: [
          Expanded(child: children[i]),
          const SizedBox(width: 6),
          Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
        ]),
      ],
    ]);
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.maxLength,
    this.code = false,
    this.onChanged,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String hint;
  final int? maxLength;

  /// A room code: four big capital letters.
  final bool code;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final style = code ? FbTxt.label(40, color: Kit.ink, spacing: 0.2) : FbTxt.typed(18, bold: true, color: Kit.ink);
    final line = UnderlineInputBorder(borderSide: BorderSide(color: Kit.ink, width: 1.5));
    return TextField(
      controller: controller,
      style: style,
      cursorColor: Kit.blaze,
      autocorrect: false,
      enableSuggestions: !code,
      textCapitalization: code ? TextCapitalization.characters : TextCapitalization.words,
      inputFormatters: [
        if (code) ...[
          FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
          LengthLimitingTextInputFormatter(4),
          TextInputFormatter.withFunction((_, v) => v.copyWith(text: v.text.toUpperCase())),
        ] else
          LengthLimitingTextInputFormatter(maxLength),
      ],
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: style.copyWith(color: Kit.graphite.withValues(alpha: 0.6)),
        counterStyle: FbTxt.typed(11, color: Kit.graphite),
        contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        border: line,
        enabledBorder: line,
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Kit.blaze, width: 2)),
      ),
    );
  }
}

/// A player as an entry in the register: their climber, name and lane,
/// a pencil tick when they are ready, and who made the room.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.lane, required this.you, required this.host});
  final RoomPlayer player;
  final ({int lane, int side}) lane;
  final bool you, host;

  @override
  Widget build(BuildContext context) {
    final k = Climber.byId(player.climber);
    return Opacity(
      opacity: player.connected ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 40, height: 52, child: ClimberPortrait(climber: k)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(player.name, overflow: TextOverflow.ellipsis, style: FbTxt.hand(30, color: you ? Kit.blaze : Kit.ink)),
              Text(player.connected ? '${k.name} · ${laneLabel(lane.lane, lane.side)}' : 'Reconnecting…',
                  style: FbTxt.typed(12.5, color: Kit.graphite, height: 1.2)),
            ]),
          ),
          if (player.ready) ...[const PencilBox(on: true, size: 20, drawIn: true), const SizedBox(width: 4), const _Tag(label: 'Ready'), const SizedBox(width: 6)],
          if (host) const _Tag(label: 'Creator'),
          if (you) ...[const SizedBox(width: 6), const _Tag(label: 'You')],
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Text(label.toUpperCase(), style: FbTxt.typed(11, bold: true, color: Kit.ink));
}

/// A dot and a word: is the server there?
class _NetChip extends StatelessWidget {
  const _NetChip({required this.status});
  final NetStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      NetStatus.online => ('Online', hex(0x3B9A5A)),
      NetStatus.connecting => ('Connecting', Kit.rope),
      NetStatus.failed => ('Offline', Kit.blaze),
      NetStatus.off => ('Offline', Kit.graphite),
    };
    return Semantics(
      label: 'Server: $label',
      excludeSemantics: true,
      child: Transform.rotate(
        angle: 0.03,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Kit.paper, boxShadow: [BoxShadow(color: rgba(0, 0, 0, 0.3), offset: const Offset(0, 4))]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label, style: FbTxt.typed(13, bold: true, color: Kit.ink, height: 1.1)),
          ]),
        ),
      ),
    );
  }
}

/// "Connecting to server…" (the free server may need a minute to wake), or
/// that it could not be reached, with Retry.
class _Connecting extends StatelessWidget {
  const _Connecting({required this.online, required this.onRetry});
  final Online online;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = online.status == NetStatus.failed || online.status == NetStatus.off;
    return PaperScrap(
      angle: failed ? 1 : -1,
      torn: false,
      child: failed
          ? Row(children: [
              Icon(Icons.cloud_off_rounded, color: Kit.blaze, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("Can't reach the server.", style: FbTxt.typed(15, bold: true, color: Kit.blaze)),
                  Text(mpServer, style: FbTxt.typed(12, color: Kit.graphite)),
                ]),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 130, child: GameButton(label: 'Retry', primary: true, onTap: onRetry)),
            ])
          : Row(children: [
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Kit.ink)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Connecting to server…', style: FbTxt.typed(15, bold: true, color: Kit.ink)),
                  if (online.slow)
                    Text('The server may be waking up. This can take up to a minute.',
                        style: Txt.body(14, color: Kit.ink, height: 1.35)),
                ]),
              ),
            ]),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Row(children: [
          Icon(Icons.error_outline_rounded, color: Kit.blaze, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: FbTxt.typed(15, bold: true, color: Kit.blaze))),
        ]),
      );
}
