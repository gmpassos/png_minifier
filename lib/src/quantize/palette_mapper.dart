import 'dart:typed_data';

import '../image/color.dart';
import '../image/color_histogram.dart';
import '../image/png_image.dart';

/// Palette entries with their premultiplied channels cached, for fast
/// bounded nearest-colour searches.
class PaletteIndex {
  /// The packed (straight-alpha) entries.
  final List<int> entries = [];
  final List<int> _premul = [];

  /// Creates an index over [colors].
  PaletteIndex([Iterable<int> colors = const []]) {
    colors.forEach(add);
  }

  /// Number of entries.
  int get length => entries.length;

  /// Appends [color].
  void add(int color) {
    entries.add(color);
    final a = alphaOf(color);
    _premul
      ..add(premultiply(redOf(color), a))
      ..add(premultiply(greenOf(color), a))
      ..add(premultiply(blueOf(color), a))
      ..add(a);
  }

  /// Whether some entry is within [maxError] (see [colorError]) of [color].
  bool covers(int color, int maxError) {
    final a = alphaOf(color);
    final r = premultiply(redOf(color), a);
    final g = premultiply(greenOf(color), a);
    final b = premultiply(blueOf(color), a);
    final p = _premul;
    for (var i = 0; i < p.length; i += 4) {
      if ((p[i + 3] - a).abs() <= maxError &&
          (p[i] - r).abs() <= maxError &&
          (p[i + 1] - g).abs() <= maxError &&
          (p[i + 2] - b).abs() <= maxError) {
        return true;
      }
    }
    return false;
  }

  /// The index of the entry closest to [color] by [colorDistance] among
  /// those within [maxError]; -1 if none. Ties go to the lower index.
  int nearest(int color, int maxError) {
    final a = alphaOf(color);
    final r = premultiply(redOf(color), a);
    final g = premultiply(greenOf(color), a);
    final b = premultiply(blueOf(color), a);
    final p = _premul;
    var best = -1;
    var bestDistance = 0;
    for (var i = 0; i < p.length; i += 4) {
      final dr = p[i] - r;
      final dg = p[i + 1] - g;
      final db = p[i + 2] - b;
      final da = p[i + 3] - a;
      if (dr.abs() > maxError ||
          dg.abs() > maxError ||
          db.abs() > maxError ||
          da.abs() > maxError) {
        continue;
      }
      final d = 2 * dr * dr + 4 * dg * dg + db * db + 3 * da * da;
      if (best < 0 || d < bestDistance) {
        best = i >> 2;
        bestDistance = d;
      }
    }
    return best;
  }
}

/// Maps every colour of [histogram] to its nearest [palette] entry within
/// [maxError]. Returns the colours that have none (empty when all map).
List<int> uncovered(
  ColorHistogram histogram,
  PaletteIndex palette,
  int maxError,
) => [
  for (final c in histogram.colors)
    if (!palette.covers(c, maxError)) c,
];

/// [image] with every pixel replaced by its nearest [palette] entry within
/// [maxError]; null if some colour has no entry in range.
PngImage? remap(
  PngImage image,
  ColorHistogram histogram,
  PaletteIndex palette,
  int maxError,
) {
  final mapping = <int, int>{};
  for (final c in histogram.colors) {
    final i = palette.nearest(c, maxError);
    if (i < 0) return null;
    mapping[c] = palette.entries[i];
  }
  final src = image.pixels;
  final out = Uint8List(src.length);
  for (var i = 0; i < image.pixelCount; i++) {
    final m = mapping[colorAt(src, i)]!;
    final o = i * 4;
    out[o] = redOf(m);
    out[o + 1] = greenOf(m);
    out[o + 2] = blueOf(m);
    out[o + 3] = alphaOf(m);
  }
  return PngImage(image.width, image.height, out);
}

/// Grows [palette] with the uncovered colours of [histogram] (most used
/// first, each one covering its neighbours within [maxError]) up to
/// [maxColors]. Returns false if [maxColors] is not enough.
bool coverRemaining(
  ColorHistogram histogram,
  PaletteIndex palette,
  int maxColors,
  int maxError,
) {
  for (final c in histogram.colors) {
    if (palette.covers(c, maxError)) continue;
    if (palette.length >= maxColors) return false;
    palette.add(c);
  }
  return true;
}
