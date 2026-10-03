import 'color.dart';
import 'png_image.dart';

/// The distinct colours of an image with their pixel counts, most used
/// first (ties by packed value, so the order is the same everywhere), plus
/// the properties that decide which PNG representations can hold it.
class ColorHistogram {
  /// Distinct packed colours, most used first.
  final List<int> colors;

  /// Pixel count of each entry of [colors].
  final List<int> counts;

  /// Every pixel has alpha 255.
  final bool opaque;

  /// Alpha is only ever 0 or 255.
  final bool binaryAlpha;

  /// Every pixel has r == g == b.
  final bool grey;

  ColorHistogram._(
    this.colors,
    this.counts, {
    required this.opaque,
    required this.binaryAlpha,
    required this.grey,
  });

  /// Counts the colours of [image].
  factory ColorHistogram.of(PngImage image) {
    final map = <int, int>{};
    final p = image.pixels;
    var opaque = true;
    var binaryAlpha = true;
    var grey = true;
    for (var o = 0; o < p.length; o += 4) {
      final a = p[o + 3];
      if (a != 255) {
        opaque = false;
        if (a != 0) binaryAlpha = false;
      }
      if (p[o] != p[o + 1] || p[o] != p[o + 2]) grey = false;
      final c = packRgba(p[o], p[o + 1], p[o + 2], a);
      map[c] = (map[c] ?? 0) + 1;
    }
    final colors = map.keys.toList()
      ..sort((x, y) {
        final byCount = map[y]!.compareTo(map[x]!);
        return byCount != 0 ? byCount : x.compareTo(y);
      });
    return ColorHistogram._(
      colors,
      [for (final c in colors) map[c]!],
      opaque: opaque,
      binaryAlpha: binaryAlpha,
      grey: grey,
    );
  }

  /// Number of distinct colours.
  int get length => colors.length;
}
