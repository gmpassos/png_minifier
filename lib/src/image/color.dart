/// Packed RGBA colours and the error measures the lossy strategies share.
///
/// A colour packs as `r·2²⁴ + g·2¹⁶ + b·2⁸ + a`: a non-negative integer below
/// 2³², so it is exact and orders the same on the VM, dart2js and dart2wasm.
library;

import 'dart:typed_data';

/// Packs one RGBA colour.
int packRgba(int r, int g, int b, int a) =>
    r * 0x1000000 + (g << 16) + (b << 8) + a;

/// The packed colour of pixel [index] in RGBA [pixels].
int colorAt(Uint8List pixels, int index) {
  final o = index * 4;
  return packRgba(pixels[o], pixels[o + 1], pixels[o + 2], pixels[o + 3]);
}

/// Red of a packed colour.
int redOf(int c) => (c >> 24) & 0xff;

/// Green of a packed colour.
int greenOf(int c) => (c >> 16) & 0xff;

/// Blue of a packed colour.
int blueOf(int c) => (c >> 8) & 0xff;

/// Alpha of a packed colour.
int alphaOf(int c) => c & 0xff;

/// [channel] premultiplied by [alpha], rounded.
int premultiply(int channel, int alpha) => (channel * alpha + 127) ~/ 255;

/// The visible difference of two colours: the largest per-channel
/// difference of alpha and the premultiplied colour. Two fully transparent
/// colours are equal whatever their RGB; a faint pixel's colour counts only
/// as much as it shows.
int colorError(int c1, int c2) {
  final a1 = alphaOf(c1);
  final a2 = alphaOf(c2);
  var e = (a1 - a2).abs();
  final dr = (premultiply(redOf(c1), a1) - premultiply(redOf(c2), a2)).abs();
  if (dr > e) e = dr;
  final dg = (premultiply(greenOf(c1), a1) - premultiply(greenOf(c2), a2))
      .abs();
  if (dg > e) e = dg;
  final db = (premultiply(blueOf(c1), a1) - premultiply(blueOf(c2), a2)).abs();
  if (db > e) e = db;
  return e;
}

/// Weighted squared distance used to choose the closest palette entry, in
/// premultiplied space with a perceptual weighting (green counts most).
int colorDistance(int c1, int c2) {
  final a1 = alphaOf(c1);
  final a2 = alphaOf(c2);
  final dr = premultiply(redOf(c1), a1) - premultiply(redOf(c2), a2);
  final dg = premultiply(greenOf(c1), a1) - premultiply(greenOf(c2), a2);
  final db = premultiply(blueOf(c1), a1) - premultiply(blueOf(c2), a2);
  final da = a1 - a2;
  return 2 * dr * dr + 4 * dg * dg + db * db + 3 * da * da;
}

/// The squared error of two colours summed over the four channels, in the
/// same space as [colorError] (for PSNR).
int colorSquaredError(int c1, int c2) {
  final a1 = alphaOf(c1);
  final a2 = alphaOf(c2);
  final dr = premultiply(redOf(c1), a1) - premultiply(redOf(c2), a2);
  final dg = premultiply(greenOf(c1), a1) - premultiply(greenOf(c2), a2);
  final db = premultiply(blueOf(c1), a1) - premultiply(blueOf(c2), a2);
  final da = a1 - a2;
  return dr * dr + dg * dg + db * db + da * da;
}

/// Luma of a packed colour (integer BT.601), for palette ordering.
int lumaOf(int c) =>
    (299 * redOf(c) + 587 * greenOf(c) + 114 * blueOf(c)) ~/ 1000;
