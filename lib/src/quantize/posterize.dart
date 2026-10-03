import 'dart:typed_data';

import '../image/png_image.dart';

/// [image] with each colour channel rounded to the nearest of the levels
/// `0, s, 2s, …, 255` for `s = 2·maxError + 1`, so no channel moves by more
/// than [maxError]; alpha is kept. Null when [maxError] is 0 or nothing
/// changes.
PngImage? posterize(PngImage image, int maxError) {
  if (maxError <= 0) return null;
  final step = 2 * maxError + 1;
  final table = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    var level = ((v + maxError) ~/ step) * step;
    if (level > 255 || 255 - v < (v - level).abs()) level = 255;
    if ((level - v).abs() > maxError) level = v;
    table[v] = level;
  }
  final src = image.pixels;
  final out = Uint8List(src.length);
  var changed = false;
  for (var o = 0; o < src.length; o += 4) {
    for (var ch = 0; ch < 3; ch++) {
      final v = table[src[o + ch]];
      if (v != src[o + ch]) changed = true;
      out[o + ch] = v;
    }
    out[o + 3] = src[o + 3];
  }
  return changed ? PngImage(image.width, image.height, out) : null;
}

/// [image] with nearly transparent pixels (alpha ≤ [maxError]) made fully
/// transparent and nearly opaque ones (alpha ≥ 255 − [maxError]) opaque —
/// often enough to drop the alpha channel or use a colour key. Null when
/// nothing changes.
PngImage? snapAlpha(PngImage image, int maxError) {
  if (maxError <= 0) return null;
  final src = image.pixels;
  final out = Uint8List.fromList(src);
  var changed = false;
  for (var o = 0; o < src.length; o += 4) {
    final a = src[o + 3];
    if (a != 0 && a <= maxError) {
      out[o] = out[o + 1] = out[o + 2] = out[o + 3] = 0;
      changed = true;
    } else if (a != 255 && a >= 255 - maxError) {
      out[o + 3] = 255;
      changed = true;
    }
  }
  return changed ? PngImage(image.width, image.height, out) : null;
}

/// [image] with every fully transparent pixel set to transparent black, so
/// they all share one colour (one palette entry, one colour key).
/// Returns [image] itself when nothing changes.
PngImage clearTransparent(PngImage image) {
  final src = image.pixels;
  Uint8List? out;
  for (var o = 0; o < src.length; o += 4) {
    if (src[o + 3] == 0 && (src[o] | src[o + 1] | src[o + 2]) != 0) {
      out ??= Uint8List.fromList(src);
      out[o] = out[o + 1] = out[o + 2] = 0;
    }
  }
  final p16 = image.pixels16;
  Uint16List? out16;
  if (p16 != null) {
    for (var o = 0; o < p16.length; o += 4) {
      if (p16[o + 3] == 0 && (p16[o] | p16[o + 1] | p16[o + 2]) != 0) {
        out16 ??= Uint16List.fromList(p16);
        out16[o] = out16[o + 1] = out16[o + 2] = 0;
      }
    }
  }
  if (out == null && out16 == null) return image;
  return PngImage(
    image.width,
    image.height,
    out ?? src,
    pixels16: out16 ?? p16,
  );
}
