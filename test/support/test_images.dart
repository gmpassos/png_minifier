import 'dart:typed_data';

import 'package:png_minifier/png_minifier.dart';

/// Synthetic images with known properties, built in code so the same
/// inputs exist on every test platform (VM, Chrome, WebAssembly).

/// A smooth RGBA gradient with varying alpha: many colours, not grey.
PngImage gradientImage(int width, int height) {
  final p = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final o = (y * width + x) * 4;
      p[o] = x * 255 ~/ (width - 1);
      p[o + 1] = y * 255 ~/ (height - 1);
      p[o + 2] = (x + y) * 255 ~/ (width + height - 2);
      p[o + 3] = 128 + (x * 127 ~/ (width - 1));
    }
  }
  return PngImage(width, height, p);
}

/// An opaque photo-like image: a gradient plus deterministic noise, so it
/// has thousands of colours.
PngImage noisyImage(int width, int height, {int seed = 1}) {
  final p = Uint8List(width * height * 4);
  // A small LCG whose products stay far below 2^53, so it is exact under
  // dart2js too.
  var s = seed;
  int next() {
    s = (s * 75 + 74) % 65537;
    return s & 0x1f;
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final o = (y * width + x) * 4;
      p[o] = (x * 200 ~/ width + next()).clamp(0, 255);
      p[o + 1] = (y * 200 ~/ height + next()).clamp(0, 255);
      p[o + 2] = (100 + next() * 3).clamp(0, 255);
      p[o + 3] = 255;
    }
  }
  return PngImage(width, height, p);
}

/// Pixel art: a sprite of [colors] flat colours (plus rare near-duplicate
/// shades when [rareShades]) on a fully transparent background.
PngImage spriteImage(
  int width,
  int height, {
  int colors = 12,
  bool rareShades = false,
  bool colouredTransparency = false,
}) {
  final p = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final o = (y * width + x) * 4;
      final inside = x > 1 && y > 1 && x < width - 2 && y < height - 2;
      if (!inside) {
        if (colouredTransparency) {
          p[o] = (x * 37) & 0xff;
          p[o + 1] = (y * 59) & 0xff;
          p[o + 2] = 7;
        }
        continue; // alpha 0
      }
      final k = ((x ~/ 3) + (y ~/ 3) * 5) % colors;
      p[o] = (k * 47) & 0xff;
      p[o + 1] = (k * 91 + 30) & 0xff;
      p[o + 2] = (k * 13 + 60) & 0xff;
      p[o + 3] = 255;
      if (rareShades && (x * 7 + y * 3) % 41 == 0) {
        // A shade a few levels off: rare, so a quantiser may merge it.
        p[o] = (p[o] + 3).clamp(0, 255);
        p[o + 1] = (p[o + 1] + 2).clamp(0, 255);
      }
    }
  }
  return PngImage(width, height, p);
}

/// An opaque greyscale image whose levels are multiples of [step].
PngImage greyImage(int width, int height, {int step = 1}) {
  final p = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final g = ((i * 7) % 256) ~/ step * step;
    p[i * 4] = p[i * 4 + 1] = p[i * 4 + 2] = g;
    p[i * 4 + 3] = 255;
  }
  return PngImage(width, height, p);
}

/// An image with true 16-bit samples (not representable in 8 bits).
PngImage deepImage(int width, int height, {bool opaque = false}) {
  final s = Uint16List(width * height * 4);
  final p = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final v = (i * 977) & 0xffff;
    s[i * 4] = v;
    s[i * 4 + 1] = v ^ 0x1234;
    s[i * 4 + 2] = 0xffff - v;
    s[i * 4 + 3] = opaque ? 0xffff : (0x8000 + i) & 0xffff;
    for (var c = 0; c < 4; c++) {
      p[i * 4 + c] = (s[i * 4 + c] * 255 + 32767) ~/ 65535;
    }
  }
  return PngImage(width, height, p, pixels16: s);
}

/// [image] encoded as plain RGBA8 PNG (the kind of file the minifier gets).
Uint8List plainPng(PngImage image, {List<PngChunk> ancillary = const []}) =>
    encodePng(
      PngRaster(
        width: image.width,
        height: image.height,
        colorType: PngColorType.rgba,
        bitDepth: 8,
        data: image.pixels,
      ),
      filter: PngFilterStrategy.none,
      level: 1,
      ancillary: ancillary,
    );
