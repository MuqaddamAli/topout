// The Field Book look: colours, type and the mountain's palettes.
// The numbers come from the mockups in design/field-book/mockups/ and are
// explained in design/field-book/HANDOFF.md. Nothing here changes the rules.
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'core.dart' show HoldType, Quality;
import 'palette.dart';

/// The kit: colours that never change on the mountain.
class Kit {
  // paper
  static final paper = hex(0xEFE6CC); // field book pages, scraps, tags
  static final card = hex(0xF7F1DE); // index cards (route and climber cards)
  static final register = hex(0xE9E1CB); // summit register pages
  static final manila = hex(0xDCC48A); // a tab that is not picked
  static final grid = rgba(110, 140, 160, 0.16); // paper grid, 16 px cells (24 px on wide pages)
  static final gridScrap = rgba(110, 140, 160, 0.30); // the finer grid on small scraps, 11 to 12 px cells
  static final rule = rgba(70, 120, 170, 0.28); // ruled lines on log pages and index cards
  static final margin = rgba(196, 42, 28, 0.55); // the red margin line
  static final tape = rgba(217, 164, 65, 0.78); // masking tape holding scraps down

  // ink and pencil
  static final ink = hex(0x1B2230); // text and outlines; blue-black, never pure black
  static final graphite = hex(0x5A5A58); // pencil notes and faded entries (5.5:1 on paper)

  // webbing: the one thing to do next
  static final webbing = hex(0xFF5B1F); // ink text on it is 5.1:1
  static final webbingDown = hex(0xE64B12); // pressed
  static final webbingEdge = rgba(120, 30, 0, 0.28); // the woven rails top and bottom, 5 px
  static final weave = rgba(90, 20, 0, 0.12); // 1 px lines every 3 px
  static final bartack = hex(0x2A140A); // the zigzag stitch on the cut end

  // on the rock
  static final chalk = hex(0xF4F1EA); // every hint drawn on the wall
  static final blaze = hex(0xC42A1C); // trail paint, danger, falls
  static final blazeWhite = hex(0xF4F1E8); // the white stripe of a blaze; also text on dark rock
  static final rope = hex(0xD9A441); // the gear sling
  static final ropeTwist = hex(0x7A5418); // the twist drawn over the rope, dashes 3 on 7
  static final teal = hex(0x1F6F8B); // carabiners, the only cool colour in the kit
  static final lampWarm = hex(0xFFE7A8); // the headlamp
  static final low = hex(0xE0412F); // a weak hand, on dark rock
  static final shade = rgba(15, 17, 20, 0.5); // the altimeter strip behind its ticks
  static final darkness = rgba(6, 9, 22, 0.78); // the night outside the headlamp
  static final frost = rgba(232, 242, 250, 0.55); // frost at the screen edges
  static final frostEdge = rgba(244, 250, 255, 0.92);
}

/// How a hold under the finger is marked in chalk. Shape carries the
/// meaning; colour only helps.
enum ChalkMark { ring, brokenRing, cross }

/// The chalk word written next to the hold you are aiming at.
String chalkWord(HoldType t) => switch (t) {
      HoldType.jug => 'jug!',
      HoldType.crimp => 'crimp',
      HoldType.sloper => 'sloper?',
      HoldType.chip => 'foot',
      HoldType.ledge => 'ledge',
      HoldType.ground => 'ground',
      HoldType.top => 'top!',
    };

/// good: a full ring. weak: a broken ring. no: a cross.
ChalkMark chalkMarkFor(Quality q) => switch (q) {
      Quality.good => ChalkMark.ring,
      Quality.weak => ChalkMark.brokenRing,
      Quality.no => ChalkMark.cross,
    };

/// The four bands of the mountain, from the bottom of a route to the top.
enum Zone { valley, cliff, ice, summit }

/// The four hours. Topout has no clock yet; see HANDOFF.md, "Time of day".
enum DayTime { dawn, day, dusk, night }

/// A band of a route by how far up it you are (0 at the start, 1 at the top).
Zone zoneAt(double progress) {
  if (progress < 0.25) return Zone.valley;
  if (progress < 0.5) return Zone.cliff;
  if (progress < 0.75) return Zone.ice;
  return Zone.summit;
}

/// The mountain's colours for one band at one hour.
class Env {
  const Env(this.skyTop, this.skyLow, this.far, this.near, this.rock, this.hold);
  final Color skyTop, skyLow, far, near, rock, hold;

  static Env of(Zone z, DayTime t) => _table[z.index][t.index];

  /// Colours between two bands, so the sky does not jump at a boundary.
  static Env lerp(Env a, Env b, double t) => Env(
        Color.lerp(a.skyTop, b.skyTop, t)!,
        Color.lerp(a.skyLow, b.skyLow, t)!,
        Color.lerp(a.far, b.far, t)!,
        Color.lerp(a.near, b.near, t)!,
        Color.lerp(a.rock, b.rock, t)!,
        Color.lerp(a.hold, b.hold, t)!,
      );

  // [zone][dawn, day, dusk, night]: sky top, sky low, far ridge, near ridge, rock, holds
  static const _table = [
    [
      Env(Color(0xFF9FA8C7), Color(0xFFF2C9A8), Color(0xFF8C93A8), Color(0xFF5E7466), Color(0xFF3B4A3E), Color(0xFFB9C48A)),
      Env(Color(0xFFA8CFE0), Color(0xFFEEF0DC), Color(0xFF9DB5B2), Color(0xFF6F8F68), Color(0xFF445A45), Color(0xFFC7D38E)),
      Env(Color(0xFF5E5A86), Color(0xFFF09A6E), Color(0xFF7D6E86), Color(0xFF4F5A55), Color(0xFF2F3A33), Color(0xFFD8A86A)),
      Env(Color(0xFF10182B), Color(0xFF2B3A5A), Color(0xFF2A3550), Color(0xFF1E2B33), Color(0xFF141E22), Color(0xFF6F8A7A)),
    ],
    [
      Env(Color(0xFFA7A6C4), Color(0xFFF3CBA6), Color(0xFF9C95A3), Color(0xFF7A6E66), Color(0xFF4E4640), Color(0xFFD8B27A)),
      Env(Color(0xFFB6CFDC), Color(0xFFF1E8D6), Color(0xFFABA79C), Color(0xFF8A8072), Color(0xFF5B524A), Color(0xFFD9BC7C)),
      Env(Color(0xFF594F7D), Color(0xFFEE8D5E), Color(0xFF806878), Color(0xFF5F4E4E), Color(0xFF3A3030), Color(0xFFE0A060)),
      Env(Color(0xFF0F1629), Color(0xFF2A3456), Color(0xFF2B3148), Color(0xFF242733), Color(0xFF17191F), Color(0xFF7D7A6E)),
    ],
    [
      Env(Color(0xFF97A9D1), Color(0xFFF2D2C2), Color(0xFF9DAFC9), Color(0xFF7F98B3), Color(0xFF3F5468), Color(0xFFD6EAF4)),
      Env(Color(0xFF8FC0E0), Color(0xFFE9F3F7), Color(0xFFA9C3D6), Color(0xFF86A7C0), Color(0xFF3E5568), Color(0xFFDDF0FA)),
      Env(Color(0xFF4C5288), Color(0xFFE79A86), Color(0xFF6F7AA0), Color(0xFF53648A), Color(0xFF2C3550), Color(0xFFB9C8E6)),
      Env(Color(0xFF0A1226), Color(0xFF1F3158), Color(0xFF22345A), Color(0xFF1B2944), Color(0xFF101A2C), Color(0xFF7FA3C8)),
    ],
    [
      Env(Color(0xFF7E8DC4), Color(0xFFF4C7C9), Color(0xFF8F95B8), Color(0xFF9AA2C0), Color(0xFF2F3448), Color(0xFFF6F1F4)),
      Env(Color(0xFF6F9ACB), Color(0xFFDCE6F2), Color(0xFF9AA8C6), Color(0xFFB5C0D6), Color(0xFF2C3246), Color(0xFFF5F7FB)),
      Env(Color(0xFF3E3A78), Color(0xFFE0889A), Color(0xFF5C5A8C), Color(0xFF6E6E96), Color(0xFF22223A), Color(0xFFE9D6E6)),
      Env(Color(0xFF060B1E), Color(0xFF18224A), Color(0xFF1A2244), Color(0xFF2A3358), Color(0xFF0C1020), Color(0xFFC9D4EE)),
    ],
  ];
}

/// Sun or moon: colour and opacity; and how bright the stars are.
({Color orb, double orbAlpha, double stars}) skyLights(DayTime t) => switch (t) {
      DayTime.dawn => (orb: const Color(0xFFF7C38E), orbAlpha: 1.0, stars: 0.25),
      DayTime.day => (orb: const Color(0xFFFFF6DA), orbAlpha: 0.9, stars: 0.0),
      DayTime.dusk => (orb: const Color(0xFFF4A46A), orbAlpha: 1.0, stars: 0.15),
      DayTime.night => (orb: const Color(0xFFE8EEF7), orbAlpha: 1.0, stars: 1.0),
    };

/// How much frost sits at the screen edges (0 to 1).
double frostAt(Zone z, DayTime t) => const [
      [0.0, 0.0, 0.0, 0.2],
      [0.1, 0.0, 0.05, 0.35],
      [0.45, 0.3, 0.4, 0.65],
      [0.6, 0.5, 0.6, 0.85],
    ][z.index][t.index];

/// How dark it is outside the headlamp (0 to 1).
double nightAt(DayTime t) => switch (t) { DayTime.night => 1.0, DayTime.dusk => 0.3, _ => 0.0 };

/// Snow falls in the two top bands.
bool snowsIn(Zone z) => z == Zone.ice || z == Zone.summit;

/// Titles on the sky use ink in daylight and paper at dusk and night.
Color titleInk(DayTime t) => t == DayTime.dusk || t == DayTime.night ? Kit.blazeWhite : Kit.ink;

/// The three hands of type. Flutter has no text-transform: write labels in
/// capitals with toUpperCase().
class FbTxt {
  /// Archivo ExtraCondensed Black: titles, buttons, the numbers you read mid-move.
  static TextStyle label(double size, {Color? color, double spacing = 0}) => TextStyle(
        fontFamily: 'ArchivoXC',
        fontSize: size,
        fontWeight: FontWeight.w900,
        height: 0.9,
        letterSpacing: size * spacing,
        color: color ?? Kit.ink,
      );

  /// Courier Prime: the log's voice. Times, heights, stats, small labels.
  static TextStyle typed(double size, {bool bold = false, Color? color, double height = 1.45, double spacing = 0}) =>
      TextStyle(
        fontFamily: 'CourierPrime',
        fontSize: size,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        height: height,
        letterSpacing: size * spacing,
        color: color ?? Kit.ink,
      );

  /// Reenie Beanie: your own hand. Chalk on the rock and pencil in margins.
  /// Short words only, and never smaller than 30 px or it cannot be read.
  static TextStyle hand(double size, {Color? color}) => TextStyle(
        fontFamily: 'Reenie',
        fontSize: math.max(30, size),
        height: 0.95,
        color: color ?? Kit.graphite,
      );
}

/// Tally marks: strokes, every fifth one crossing the four before it.
/// Drawn with a 2.6 px round-capped stroke, in a box 28 px high.
Path tallyPath(int n, {double x0 = 6}) {
  final p = Path();
  var x = x0;
  for (var i = 1; i <= n; i++) {
    if (i % 5 == 0) {
      p.moveTo(x - 34, 20);
      p.lineTo(x - 2, 6);
      x += 10;
    } else {
      p.moveTo(x, 4);
      p.lineTo(x - 1.5, 24);
      x += 8;
    }
  }
  return p;
}

/// The bar-tack stitch on the cut end of a webbing strap: a zigzag of
/// [teeth] strokes in a [size] box, 1.7 px.
Path bartackPath(Size size, {int teeth = 5}) {
  final p = Path()..moveTo(3, 4);
  final step = (size.width - 6) / teeth;
  for (var i = 1; i <= teeth; i++) {
    p.lineTo(3 + i * step, i.isOdd ? size.height - 4 : 4);
  }
  return p;
}
