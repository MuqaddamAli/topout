import 'dart:ui';

/// 0xRRGGBB to an opaque colour.
Color hex(int rgb) => Color(0xFF000000 | rgb);

/// Colour with alpha from 0 to 1.
Color rgba(int r, int g, int b, double a) => Color.fromRGBO(r, g, b, a.clamp(0.0, 1.0));

/// The colours of the scene that the Field Book (field_book.dart, [Kit]) does
/// not set: the dark behind everything, the light tint of good, weak and
/// bad holds on chalk marks, the ground and its crash pads, and the lamps.
class Pal {
  static final ink = hex(0x11141b);
  static final good = hex(0x7fdc95);
  static final weak = hex(0xf4c64d);
  static final bad = hex(0xff5a5a);
  static final earthTop = hex(0x3a332b);
  static final grass = hex(0x5b6b43);
  static final pad = hex(0x203457);
  static final padTop = hex(0x2e4c7c);
  static final lamp = hex(0xffd27a);
}

/// Gear every climber shares: base, shade, light.
class Body {
  static final harness = [hex(0x2b2f3a), hex(0x191c23), hex(0x4a5060)];
  static final quickdraws = [hex(0x9ad14b), hex(0xff5b8a), hex(0x4fb3ff), hex(0xffd23f)];
}

enum HairStyle { ponytail, braid, bun, short }

/// What a climber wears on the head.
enum Headwear { helmet, beanie, headband, sweatband }

/// What a climber wears on top: a T-shirt, a racerback tank top, a hoodie
/// (its hood down on the back) or a loose T-shirt with rolled sleeves.
enum TopStyle { tee, tank, hoodie, rolledTee }

/// What a climber wears on the legs: climbing pants with rolled cuffs, three
/// quarter pants (bare shins, socks), leggings with a stripe, or loose
/// joggers gathered at the ankle.
enum LegStyle { pants, capris, leggings, joggers }

/// The shape of a climber's body, only for drawing (the rules use the
/// climber's reach). 1 is the original climber.
class Build {
  const Build({this.chest = 1, this.waist = 1, this.limb = 1, this.head = 1, this.neck = 0, this.hand = 1});

  /// How wide the shoulders and chest are, and the waist.
  final double chest, waist;

  /// How thick the arms and legs are.
  final double limb;

  /// The size of the head and the hands, and how much longer the neck is (units).
  final double head, hand, neck;
}

/// How a climber looks: colours (base, shade, light), body and clothes.
class Look {
  const Look({
    required this.shirt,
    required this.skin,
    required this.pants,
    required this.patch,
    required this.shoe,
    required this.helmet,
    required this.stripe,
    required this.hair,
    required this.bag,
    required this.hairStyle,
    required this.headwear,
    required this.top,
    required this.legs,
    this.build = const Build(),
    this.tape = false,
    this.band,
  });
  final List<Color> shirt, skin, pants, shoe, hair, bag;

  /// Cuffs, socks, the stripe on leggings, a hood's lining.
  final List<Color> patch;

  /// The helmet, beanie, headband or sweatband.
  final List<Color> helmet;

  /// The stripe on the helmet (or the beanie's pompom) and the tab on the shoes.
  final Color stripe;
  final HairStyle hairStyle;
  final Headwear headwear;
  final TopStyle top;
  final LegStyle legs;
  final Build build;

  /// Tape on the fingers.
  final bool tape;

  /// Sweatbands on the wrists, if any.
  final Color? band;

  /// Points in the hair chain that swings (0 for hair that does not).
  int get tailLinks => switch (hairStyle) { HairStyle.ponytail => 5, HairStyle.braid => 8, _ => 0 };
  double get tailLink => hairStyle == HairStyle.braid ? 3.4 : 3.5;

  static List<Color> _c(int a, int b, int c) => [hex(a), hex(b), hex(c)];

  static final Map<String, Look> _looks = {
    // the all-rounder: helmet, ponytail, a T-shirt and climbing pants
    'ada': Look(
      shirt: _c(0xff7a2f, 0xd4571e, 0xffab70),
      skin: _c(0xe9a882, 0xc47e5c, 0xffd2b0),
      pants: _c(0x2c3659, 0x1d2442, 0x46558a),
      patch: _c(0x3e4b77, 0x2a3358, 0x5a6aa0),
      shoe: _c(0x21a08f, 0x167a6d, 0x5ed2c2),
      helmet: _c(0xf5f1ea, 0xcfc7ba, 0xffffff),
      stripe: hex(0xff7a2f),
      hair: _c(0x7a5238, 0x58391f, 0xa8774f),
      bag: _c(0xf0bd45, 0xc4932a, 0xffe08a),
      hairStyle: HairStyle.ponytail,
      headwear: Headwear.helmet,
      top: TopStyle.tee,
      legs: LegStyle.pants,
      build: Build(waist: 0.96),
    ),
    // long reach: tall and lanky, a beanie, a tank top and three quarter pants
    'rio': Look(
      shirt: _c(0x3f86e0, 0x2c66b8, 0x7fb4f5),
      skin: _c(0x9a6243, 0x774a31, 0xc48a66),
      pants: _c(0x5d6840, 0x434b2c, 0x84915f),
      patch: _c(0xeceae4, 0xc9c6bd, 0xffffff),
      shoe: _c(0xf08a24, 0xc2681a, 0xffb866),
      helmet: _c(0xe2a63a, 0xb98225, 0xf6cd76),
      stripe: hex(0xd8493c),
      hair: _c(0x2a2420, 0x17120f, 0x4f4239),
      bag: _c(0xe0483f, 0xb0322a, 0xff8a7f),
      hairStyle: HairStyle.short,
      headwear: Headwear.beanie,
      top: TopStyle.tank,
      legs: LegStyle.capris,
      build: Build(chest: 0.93, waist: 0.9, limb: 0.86, head: 0.97, neck: 2.5, hand: 1.05),
    ),
    // small holds: small and compact, a headband, a hoodie, leggings, taped fingers
    'mei': Look(
      shirt: _c(0xe0508a, 0xb53a6c, 0xff94bc),
      skin: _c(0xf2c09c, 0xd09a78, 0xffe0c8),
      pants: _c(0x34343f, 0x23232b, 0x51515f),
      patch: _c(0xff94bc, 0xe0508a, 0xffc4da),
      shoe: _c(0x8a5bd6, 0x6a42a8, 0xb693f2),
      helmet: _c(0x8fdcc2, 0x63b399, 0xc8f6e6),
      stripe: hex(0xe0508a),
      hair: _c(0x231e22, 0x120e10, 0x4a3f46),
      bag: _c(0x2bb3a3, 0x1c8a7d, 0x72e2d4),
      hairStyle: HairStyle.braid,
      headwear: Headwear.headband,
      top: TopStyle.hoodie,
      legs: LegStyle.leggings,
      build: Build(chest: 0.9, waist: 0.9, limb: 0.9, head: 0.94, neck: -0.5, hand: 0.9),
      tape: true,
    ),
    // the jumper: broad and springy, a sweatband and a top knot, a loose
    // T-shirt with rolled sleeves, joggers and wristbands
    'kai': Look(
      shirt: _c(0x93cc45, 0x6f9e2c, 0xc6f08a),
      skin: _c(0xd29a72, 0xae7653, 0xf2c3a0),
      pants: _c(0x5b606c, 0x41454f, 0x80869a),
      patch: _c(0x4b505a, 0x363a42, 0x6a707e),
      shoe: _c(0x3a6fd8, 0x2a54a8, 0x7ea4f2),
      helmet: _c(0xe2483b, 0xb3342a, 0xff8a7f),
      stripe: hex(0xf5f1ea),
      hair: _c(0x4a3426, 0x302016, 0x6e5240),
      bag: _c(0xff9a3c, 0xd27520, 0xffc27a),
      hairStyle: HairStyle.bun,
      headwear: Headwear.sweatband,
      top: TopStyle.rolledTee,
      legs: LegStyle.joggers,
      build: Build(chest: 1.14, waist: 1.02, limb: 1.13, neck: -1, hand: 1.05),
      band: hex(0xe2483b),
    ),
  };

  static Look of(String id) => _looks[id] ?? _looks['ada']!;
}
