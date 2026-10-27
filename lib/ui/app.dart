import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/game.dart';
import '../game/palette.dart';
import '../game/scene.dart';
import 'cards.dart';
import 'hud.dart';
import 'menu.dart';

class TopoutApp extends StatelessWidget {
  const TopoutApp({super.key, required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Topout',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Pal.ink,
        fontFamily: 'Atkinson',
        colorScheme: ColorScheme.dark(primary: Pal.signal, surface: Pal.ink2),
      ),
      home: GameScreen(game: game),
    );
  }
}

/// The whole game: the painted world with the overlays on top.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.game});
  final Game game;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  late final ScenePainter _painter;
  final FocusNode _focus = FocusNode(debugLabel: 'game');

  Game get game => widget.game;

  @override
  void initState() {
    super.initState();
    _painter = ScenePainter(game);
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addObserver(this);
    // On the web, sound may only start after the first tap.
    if (!kIsWeb) game.audio.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    game.frame(dt);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      game.audio.resume();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      game.pause();
      game.audio.suspend();
    } else if (state == AppLifecycleState.inactive) {
      game.pause();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = HardwareKeyboard.instance;
    return game.key(e.logicalKey, ctrl: k.isControlPressed || k.isMetaPressed)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  bool _isTouch(PointerDeviceKind kind) => kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus;

  @override
  Widget build(BuildContext context) {
    game.reducedMotion = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: Pal.ink,
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Listener(
            // any tap can start the sound (needed on the web)
            onPointerDown: (_) => game.audio.start(),
            behavior: HitTestBehavior.translucent,
            child: LayoutBuilder(builder: (context, c) {
              game.setViewport(c.biggest);
              return Stack(children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) => game.pointerDown(e.pointer, e.localPosition, _isTouch(e.kind)),
                    onPointerMove: (e) => game.pointerMove(e.pointer, e.localPosition),
                    onPointerUp: (e) => game.pointerUp(e.pointer),
                    onPointerCancel: (e) => game.pointerUp(e.pointer, cancelled: true),
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _painter, size: Size.infinite),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: game.uiChanged,
                    builder: (context, _) => _overlay(),
                  ),
                ),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  /// The widgets on top of the scene. The title screen and the HUD cross-fade,
  /// and the cards come in and go out softly.
  Widget _overlay() {
    final screen = game.screen;
    final fall = game.fallCard, top = game.topCard;
    final Widget? card = switch (screen) {
      Screen.fallCard when fall != null => FallCard(game: game, data: fall),
      Screen.topCard when top != null => TopCard(game: game, data: top),
      Screen.pause => PauseCard(game: game),
      _ => null,
    };
    final menu = screen == Screen.menu;
    return Stack(children: [
      Positioned.fill(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(key: ValueKey(menu), child: menu ? MenuScreen(game: game) : Hud(game: game)),
        ),
      ),
      Positioned.fill(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          reverseDuration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
          child: card == null ? const SizedBox.shrink() : KeyedSubtree(key: ValueKey(screen), child: card),
        ),
      ),
    ]);
  }
}
