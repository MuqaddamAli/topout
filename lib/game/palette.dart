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

/// Climber colours: base, shade, light.
class Body {
  static final shirt = [hex(0xff7a2f), hex(0xc94d1a), hex(0xffb07a)];
  static final skin = [hex(0xe9a882), hex(0xbf7656), hex(0xffd2b0)];
  static final pants = [hex(0x2c3659), hex(0x1b2140), hex(0x4a5986)];
  static final patch = [hex(0x3e4b77), hex(0x2a3358), hex(0x5a6aa0)];
  static final shoe = [hex(0x21a08f), hex(0x146f63), hex(0x66d6c6)];
  static final helmet = [hex(0xf5f1ea), hex(0xc4bcb0), hex(0xffffff)];
  static final hair = [hex(0x7a5238), hex(0x553722), hex(0xa8774f)];
  static final harness = [hex(0x2b2f3a), hex(0x191c23), hex(0x4a5060)];
  static final bag = [hex(0xf0bd45), hex(0xb88a22), hex(0xffe08a)];
  static final quickdraws = [hex(0x9ad14b), hex(0xff5b8a), hex(0x4fb3ff), hex(0xffd23f)];
}
