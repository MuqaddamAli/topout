// Pictures drawn once into images, so drawing them again is cheap.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// A picture drawn once into an image, to be drawn again cheaply.
///
/// On the web (skwasm), `Picture.toImageSync` gives a lazy image that is drawn
/// again from its picture every time it is used, so pre-drawn art would cost
/// almost as much as drawing it live. There the pixels are read back once and
/// turned into a plain image, which then replaces [image]; listeners hear
/// about the swap. Until then, and if reading back fails, the lazy image is
/// shown: it looks the same, only it is slower.
class Baked extends ChangeNotifier {
  Baked(ui.Picture picture, this.width, this.height) : image = picture.toImageSync(width, height) {
    if (kIsWeb) {
      _picture = picture;
      for (var y = 0; y < height; y += _Piece.max) {
        for (var x = 0; x < width; x += _Piece.max) {
          _todo.add(_Piece(this, x, y, math.min(_Piece.max, width - x), math.min(_Piece.max, height - y)));
        }
      }
      _ReadBack.add(this);
    } else {
      picture.dispose();
    }
  }

  final int width, height;
  ui.Image image;

  ui.Picture? _picture;
  Uint8List? _pixels;
  final List<_Piece> _todo = [];

  /// Every piece is in: swap in the plain image.
  void _done() {
    final pixels = _pixels!, lazy = image;
    _drop();
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, (plain) {
      image = plain;
      lazy.dispose();
      notifyListeners();
    });
  }

  void _drop() {
    _picture?.dispose();
    _picture = null;
    _pixels = null;
    _todo.clear();
  }
}

/// Records [draw] on a canvas of [width] x [height] pixels and bakes it.
Baked bake(int width, int height, void Function(ui.Canvas c) draw) {
  final rec = ui.PictureRecorder();
  draw(ui.Canvas(rec));
  return Baked(rec.endRecording(), width, height);
}

/// A part of a [Baked] image, [w] x [h] pixels from ([sx], [sy]), and where
/// it sits in a probe ([x], [y]).
class _Piece {
  _Piece(this.owner, this.sx, this.sy, this.w, this.h);
  static const int max = 512;
  final Baked owner;
  final int sx, sy, w, h;
  int x = 0, y = 0;
}

/// Reads baked pictures back on the web.
///
/// skwasm reads an image back on the same surface it draws frames on, and
/// resizes that surface to the image first. A frame drawn in between would
/// come out clipped (a flash), and so would an image read back while a frame
/// has resized it. So every read-back here is one "probe" exactly the size of
/// the frame (the surface is never resized), with as many pieces of the
/// waiting images packed into it as fit. A marker in the probe's last pixel,
/// in a new colour each time, shows that nothing was clipped all the same.
abstract final class _ReadBack {
  static final List<Baked> _waiting = [];
  static bool _running = false;
  static int _marks = 0;

  static void add(Baked b) {
    _waiting.add(b);
    if (_running) return;
    _running = true;
    // a moment later, so the images made in the same frame share a probe
    Timer.run(_run);
  }

  static Future<void> _run() async {
    var misses = 0;
    try {
      while (_waiting.isNotEmpty && misses < 6) {
        final size = ui.PlatformDispatcher.instance.implicitView?.physicalSize ?? ui.Size.zero;
        final fw = size.width.round(), fh = size.height.round();
        final pieces = _layout(fw - 1, fh - 1);
        if (pieces.isNotEmpty && await _probe(pieces, fw, fh)) {
          misses = 0;
        } else {
          misses++;
          await Future<void>.delayed(Duration(milliseconds: 50 << misses));
        }
      }
    } catch (e) {
      debugPrint('Could not read back baked images: $e');
    } finally {
      if (_waiting.isNotEmpty) {
        debugPrint('${_waiting.length} baked images stay lazy (they look the same, only slower)');
        for (final b in _waiting) {
          b._drop();
        }
        _waiting.clear();
      }
      _running = false;
    }
  }

  /// Packs waiting pieces into a probe of [w] x [h] pixels, in rows.
  static List<_Piece> _layout(int w, int h) {
    final placed = <_Piece>[];
    var x = 0, y = 0, rowH = 0;
    for (final b in _waiting) {
      for (final p in b._todo) {
        if (p.w > w || p.h > h) continue;
        if (x + p.w > w) {
          x = 0;
          y += rowH;
          rowH = 0;
        }
        if (y + p.h > h) return placed;
        p
          ..x = x
          ..y = y;
        placed.add(p);
        x += p.w;
        rowH = math.max(rowH, p.h);
      }
    }
    return placed;
  }

  /// Draws [pieces] into one probe, reads it back and hands out the pixels.
  /// False if the probe came back clipped.
  static Future<bool> _probe(List<_Piece> pieces, int fw, int fh) async {
    final mark = ++_marks, r = mark & 0xff, g = (mark >> 8) & 0xff;
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    for (final p in pieces) {
      c
        ..save()
        ..clipRect(ui.Rect.fromLTWH(p.x.toDouble(), p.y.toDouble(), p.w.toDouble(), p.h.toDouble()))
        ..translate((p.x - p.sx).toDouble(), (p.y - p.sy).toDouble())
        ..drawPicture(p.owner._picture!)
        ..restore();
    }
    c.drawRect(ui.Rect.fromLTWH(fw - 1.0, fh - 1.0, 1, 1), ui.Paint()..color = ui.Color.fromARGB(255, r, g, 0x5a));
    final picture = rec.endRecording();
    final probe = picture.toImageSync(fw, fh);
    picture.dispose();
    final ByteData? data;
    try {
      data = await probe.toByteData();
    } finally {
      probe.dispose();
    }
    if (data == null || data.lengthInBytes != fw * fh * 4) return false;
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), end = bytes.length - 4;
    if (bytes[end] != r || bytes[end + 1] != g || bytes[end + 2] != 0x5a || bytes[end + 3] != 255) return false;
    for (final p in pieces) {
      final b = p.owner, out = b._pixels ??= Uint8List(b.width * b.height * 4);
      for (var row = 0; row < p.h; row++) {
        final from = ((p.y + row) * fw + p.x) * 4, to = ((p.sy + row) * b.width + p.sx) * 4;
        out.setRange(to, to + p.w * 4, bytes, from);
      }
      b._todo.remove(p);
      if (b._todo.isEmpty) {
        _waiting.remove(b);
        b._done();
      }
    }
    return true;
  }
}
