import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/audio.dart';
import '../game/core.dart';
import '../game/game.dart';
import '../game/online.dart';
import '../game/palette.dart';
import 'climbers.dart';
import 'hud.dart' show FrameSelect, GameToast;
import 'widgets.dart';

/// Play online: make a room or join one with its code, then the lobby with
/// everyone in the room until the creator starts the climb.
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
                colors: [rgba(13, 15, 21, 0), rgba(13, 15, 21, 0.9), Pal.ink],
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
                      minHeight: 44,
                      onTap: () => _tap(game.leaveOnline),
                    ),
                    const Spacer(),
                    _NetChip(status: online.status),
                  ]),
                  SizedBox(height: math.min(size.height * 0.16, 130)),
                  Stagger(
                    index: 0,
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'PLAY '),
                        TextSpan(text: 'ONLINE', style: TextStyle(color: Pal.signal)),
                      ]),
                      style: Txt.display(52, weight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Stagger(
                    index: 1,
                    child: Text('Climb the same wall with up to 8 friends, each on their own device.',
                        style: Txt.body(16, color: Pal.chalkDim, height: 1.4)),
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
        top: pad.top + 70,
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GamePanel(title: 'Your name', children: [
        _Field(
          controller: _name,
          hint: 'Name others will see',
          maxLength: 16,
          onChanged: (v) => setState(() => game.playerName = v.trim()),
        ),
      ]),
      const SizedBox(height: 12),
      GamePanel(title: 'Make a room', children: [
        Text('ROUTE', style: Txt.eyebrow()),
        _Pairs(children: [
          for (final r in game.routes)
            GameChoice(label: r.name, on: _route == r.id, onTap: () => _tap(() => setState(() => _route = r.id))),
        ]),
        Text('MODE', style: Txt.eyebrow()),
        Row(children: [
          for (final m in Mode.values) ...[
            if (m != Mode.values.first) const SizedBox(width: 6),
            Expanded(child: GameChoice(label: m.label, on: _mode == m, onTap: () => _tap(() => setState(() => _mode = m)))),
          ],
        ]),
        GameButton(label: 'Create', primary: true, minHeight: 52, width: double.infinity, onTap: ready ? () => _tap(_create) : null),
      ]),
      const SizedBox(height: 12),
      GamePanel(title: 'Join a room', children: [
        Row(children: [
          Expanded(
            child: _Field(
              controller: _code,
              hint: 'CODE',
              code: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: ready ? (_) => _join() : null,
            ),
          ),
          const SizedBox(width: 10),
          GameButton(
            label: 'Join',
            primary: true,
            minHeight: 56,
            onTap: ready && cleanRoomCode(_code.text).length == 4 ? () => _tap(_join) : null,
          ),
        ]),
      ]),
      if (online.error case final e?) ...[const SizedBox(height: 14), _ErrorLine(e)],
    ]);
  }

  // ---------------------------------------------------------------- lobby

  Widget _lobby(RoomView room) {
    final route = game.routes.where((r) => r.id == room.route).firstOrNull;
    final daily = route?.endless ?? false;
    final host = room.player(room.host);
    final facts = [route?.name ?? room.route, Mode.fromName(room.mode).label, if (daily) room.dateKey].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GamePanel(title: 'Room code', children: [
        Row(children: [
          Expanded(
            child: SelectableText(room.code,
                semanticsLabel: room.code.split('').join(' '),
                style: Txt.display(64, weight: FontWeight.w900, spacing: 0.1, color: Pal.signal)),
          ),
          GameButton(
            label: _copied ? 'Copied' : 'Copy',
            icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
            minHeight: 46,
            onTap: () => _tap(() => _copy(room.code)),
          ),
        ]),
        Text('Send this code to your friends so they can join.', style: Txt.body(15, color: Pal.chalkDim)),
        Text(facts, style: Txt.mono(13, color: Pal.chalkDim)),
      ]),
      const SizedBox(height: 12),
      GamePanel(title: 'Players', children: [
        Text('${room.players.length}/${room.max} players', style: Txt.mono(14, color: Pal.good)),
        for (final p in room.players) _PlayerRow(player: p, you: p.id == online.you, host: p.id == room.host),
      ]),
      const SizedBox(height: 18),
      Text('YOUR CLIMBER', style: Txt.eyebrow()),
      const SizedBox(height: 10),
      ClimberPicker(game: game),
      const SizedBox(height: 18),
      if (online.error case final e?) ...[_ErrorLine(e), const SizedBox(height: 12)],
      if (room.started)
        FrameSelect<int>(
          game: game,
          select: (g) => (g.countdown ?? 0).ceil(),
          builder: (context, left) => Text(left > 0 ? 'Starting in $left' : 'Starting…',
              textAlign: TextAlign.center, style: Txt.display(28, color: Pal.good)),
        )
      else if (online.isHost)
        GameButton(
          label: 'Start',
          primary: true,
          minHeight: 56,
          icon: Icons.flag_rounded,
          onTap: online.status == NetStatus.online && !online.busy ? () => _tap(online.start) : null,
        )
      else
        Text('Waiting for ${host?.name ?? 'the creator'} to start…',
            textAlign: TextAlign.center, style: Txt.body(16, color: Pal.chalkDim)),
    ]);
  }
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
    final style = code ? Txt.mono(26).copyWith(letterSpacing: 8) : Txt.body(17);
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none);
    return TextField(
      controller: controller,
      style: style,
      cursorColor: Pal.signal,
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
        hintStyle: style.copyWith(color: Pal.chalkDim.withAlpha(110)),
        filled: true,
        fillColor: Pal.ink3,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: BorderSide(color: Pal.signal, width: 1.5)),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.you, required this.host});
  final RoomPlayer player;
  final bool you, host;

  @override
  Widget build(BuildContext context) {
    final k = Climber.byId(player.climber);
    return Opacity(
      opacity: player.connected ? 1 : 0.5,
      child: Row(children: [
        SizedBox(width: 40, height: 52, child: ClimberPortrait(climber: k)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(player.name, overflow: TextOverflow.ellipsis, style: Txt.body(16, weight: FontWeight.w700, height: 1.2)),
            Text(player.connected ? k.name : 'Reconnecting…', style: Txt.body(13, color: Pal.chalkDim, height: 1.2)),
          ]),
        ),
        if (host) _Tag(label: 'Creator', color: Pal.lamp),
        if (you) ...[const SizedBox(width: 6), _Tag(label: 'You', color: Pal.jump)],
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withAlpha(36), borderRadius: BorderRadius.circular(6)),
        child: Text(label.toUpperCase(), style: Txt.body(11, weight: FontWeight.w700, color: color).copyWith(letterSpacing: 0.8)),
      );
}

/// A dot and a word: is the server there?
class _NetChip extends StatelessWidget {
  const _NetChip({required this.status});
  final NetStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      NetStatus.online => ('Online', Pal.good),
      NetStatus.connecting => ('Connecting', Pal.weak),
      NetStatus.failed => ('Offline', Pal.bad),
      NetStatus.off => ('Offline', Pal.chalkDim),
    };
    return Semantics(
      label: 'Server: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Pal.ink2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Pal.line, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: Txt.body(13, weight: FontWeight.w700, height: 1.1)),
        ]),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Pal.ink2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: failed ? Pal.bad.withAlpha(140) : Pal.line, width: 1.5),
      ),
      child: failed
          ? Row(children: [
              Icon(Icons.cloud_off_rounded, color: Pal.bad, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("Can't reach the server.", style: Txt.body(16, weight: FontWeight.w700)),
                  Text(mpServer, style: Txt.mono(12, color: Pal.chalkDim)),
                ]),
              ),
              const SizedBox(width: 10),
              GameButton(label: 'Retry', primary: true, minHeight: 44, onTap: onRetry),
            ])
          : Row(children: [
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Pal.weak)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Connecting to server…', style: Txt.body(16, weight: FontWeight.w700)),
                  if (online.slow)
                    Text('The server may be waking up. This can take up to a minute.',
                        style: Txt.body(14, color: Pal.chalkDim, height: 1.35)),
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
          Icon(Icons.error_outline_rounded, color: Pal.bad, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Txt.body(15, weight: FontWeight.w700, color: Pal.bad))),
        ]),
      );
}
