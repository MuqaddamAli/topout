import 'dart:ui';

/// 0xRRGGBB to an opaque colour.
Color hex(int rgb) => Color(0xFF000000 | rgb);

/// Colour with alpha from 0 to 1.
Color rgba(int r, int g, int b, double a) => Color.fromRGBO(r, g, b, a.clamp(0.0, 1.0));

class Pal {
  static final ink = hex(0x11141b);
  static final ink2 = hex(0x1b2029);
  static final ink3 = hex(0x262c37);
  static final line = hex(0x394150);
  static final chalk = hex(0xf2ede4);
  static final chalkDim = hex(0xaca8a0);
  static final signal = hex(0xff7a2f);
  static final signalInk = hex(0x1a0e06);
  static final good = hex(0x7fdc95);
  static final weak = hex(0xf4c64d);
  static final bad = hex(0xff5a5a);
  static final jump = hex(0x7cc8ff);
  static final earth = hex(0x2a2521);
  static final earthTop = hex(0x3a332b);
  static final grass = hex(0x5b6b43);
  static final pad = hex(0x203457);
  static final padTop = hex(0x2e4c7c);
  static final outline = hex(0x15171e);
  static final lamp = hex(0xffd27a);
}

/// Gear every climber shares: base, shade, light.
class Body {
  static final harness = [hex(0x2b2f3a), hex(0x191c23), hex(0x4a5060)];
  static final quickdraws = [hex(0x9ad14b), hex(0xff5b8a), hex(0x4fb3ff), hex(0xffd23f)];
}

enum HairStyle { ponytail, braid, bun, short }

/// How a climber looks: colours (base, shade, light) and hair.
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
  });
  final List<Color> shirt, skin, pants, patch, shoe, helmet, hair, bag;

  /// The stripe on the helmet and the tab on the shoes.
  final Color stripe;
  final HairStyle hairStyle;

  /// Points in the hair chain that swings (0 for hair that does not).
  int get tailLinks => switch (hairStyle) { HairStyle.ponytail => 5, HairStyle.braid => 8, _ => 0 };
  double get tailLink => hairStyle == HairStyle.braid ? 3.4 : 3.5;

  static List<Color> _c(int a, int b, int c) => [hex(a), hex(b), hex(c)];

  static final Map<String, Look> _looks = {
    'ada': Look(
      shirt: _c(0xff7a2f, 0xc94d1a, 0xffb07a),
      skin: _c(0xe9a882, 0xbf7656, 0xffd2b0),
      pants: _c(0x2c3659, 0x1b2140, 0x4a5986),
      patch: _c(0x3e4b77, 0x2a3358, 0x5a6aa0),
      shoe: _c(0x21a08f, 0x146f63, 0x66d6c6),
      helmet: _c(0xf5f1ea, 0xc4bcb0, 0xffffff),
      stripe: hex(0xff7a2f),
      hair: _c(0x7a5238, 0x553722, 0xa8774f),
      bag: _c(0xf0bd45, 0xb88a22, 0xffe08a),
      hairStyle: HairStyle.ponytail,
    ),
    'rio': Look(
      shirt: _c(0x3f86e0, 0x2a5fae, 0x86b9f7),
      skin: _c(0x9a6243, 0x6e4129, 0xc48a66),
      pants: _c(0x55603b, 0x3a4227, 0x7a8757),
      patch: _c(0x66734a, 0x485232, 0x8c9a68),
      shoe: _c(0xf08a24, 0xb5600f, 0xffb866),
      helmet: _c(0xf4c64d, 0xc49a26, 0xffe39a),
      stripe: hex(0x2a5fae),
      hair: _c(0x2a2420, 0x17120f, 0x4f4239),
      bag: _c(0xe0483f, 0xa62c25, 0xff8a7f),
      hairStyle: HairStyle.short,
    ),
    'mei': Look(
      shirt: _c(0xe0508a, 0xa83262, 0xff94bc),
      skin: _c(0xf2c09c, 0xc99070, 0xffe0c8),
      pants: _c(0x2e2e38, 0x1c1c24, 0x4a4a58),
      patch: _c(0x40404e, 0x2a2a34, 0x5e5e70),
      shoe: _c(0x8a5bd6, 0x5f3aa0, 0xb693f2),
      helmet: _c(0x9fe0c8, 0x6fb09a, 0xd4f8ec),
      stripe: hex(0xe0508a),
      hair: _c(0x231e22, 0x100c0e, 0x463b41),
      bag: _c(0x2bb3a3, 0x1a8074, 0x72e2d4),
      hairStyle: HairStyle.braid,
    ),
    'kai': Look(
      shirt: _c(0x93cc45, 0x649426, 0xc6f08a),
      skin: _c(0xd29a72, 0xa66d4c, 0xf2c3a0),
      pants: _c(0x4b505c, 0x30343e, 0x6e7484),
      patch: _c(0x5c6270, 0x3e4350, 0x808796),
      shoe: _c(0x3a6fd8, 0x254c9c, 0x7ea4f2),
      helmet: _c(0xe2483b, 0xa82e25, 0xff8a7f),
      stripe: hex(0xf5f1ea),
      hair: _c(0xd9a84a, 0xa87a28, 0xf5d68a),
      bag: _c(0xff9a3c, 0xc46a14, 0xffc27a),
      hairStyle: HairStyle.bun,
    ),
  };

  static Look of(String id) => _looks[id] ?? _looks['ada']!;
}
