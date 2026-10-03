import 'dart:typed_data';

import '../image/color.dart';
import '../image/png_image.dart';
import 'palette_mapper.dart';

/// [v] / 16 rounded half up. Not `(v + 8) >> 4`: dart2js shifts negative
/// numbers as unsigned 32-bit, so that would differ on the web.
int _roundDiv16(int v) {
  final n = v + 8;
  final q = n ~/ 16;
  return n < 0 && q * 16 != n ? q - 1 : q;
}

/// Floyd–Steinberg dithering of [image] onto [palette], with the error
/// bound held: each pixel may only take an entry within [maxError] of its
/// original colour, so diffusion never pushes a pixel out of range. The
/// arithmetic is integer, so the result is the same on every platform.
/// Null if some colour has no entry within [maxError].
PngImage? ditherFloydSteinberg(
  PngImage image,
  PaletteIndex palette,
  int maxError,
) {
  final w = image.width;
  final h = image.height;
  final src = image.pixels;
  final out = Uint8List(src.length);
  // Accumulated error ×16 for this row and the next, 4 channels each.
  var errRow = Int32List((w + 2) * 4);
  var errNext = Int32List((w + 2) * 4);
  final candidates = <int, List<int>>{};
  final entries = palette.entries;

  List<int>? inRange(int color) {
    final cached = candidates[color];
    if (cached != null) return cached;
    final list = <int>[
      for (var e = 0; e < entries.length; e++)
        if (colorError(entries[e], color) <= maxError) e,
    ];
    if (list.isEmpty) return null;
    return candidates[color] = list;
  }

  for (var y = 0; y < h; y++) {
    errNext.fillRange(0, errNext.length, 0);
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final o = i * 4;
      final color = colorAt(src, i);
      final options = inRange(color);
      if (options == null) return null;
      final e = (x + 1) * 4;
      final transparent = src[o + 3] == 0;
      final want = [
        for (var ch = 0; ch < 4; ch++)
          transparent
              ? src[o + ch]
              : (src[o + ch] + _roundDiv16(errRow[e + ch])).clamp(0, 255),
      ];
      final target = packRgba(want[0], want[1], want[2], want[3]);
      var best = options.first;
      var bestDistance = colorDistance(entries[best], target);
      for (final k in options.skip(1)) {
        final d = colorDistance(entries[k], target);
        if (d < bestDistance) {
          best = k;
          bestDistance = d;
        }
      }
      final chosen = entries[best];
      out[o] = redOf(chosen);
      out[o + 1] = greenOf(chosen);
      out[o + 2] = blueOf(chosen);
      out[o + 3] = alphaOf(chosen);
      if (transparent) continue;
      for (var ch = 0; ch < 4; ch++) {
        final err = want[ch] - out[o + ch];
        if (err == 0) continue;
        errRow[e + 4 + ch] += err * 7;
        errNext[e - 4 + ch] += err * 3;
        errNext[e + ch] += err * 5;
        errNext[e + 4 + ch] += err;
      }
    }
    final t = errRow;
    errRow = errNext;
    errNext = t;
  }
  return PngImage(w, h, out);
}
