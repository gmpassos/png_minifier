import '../image/color.dart';
import '../image/color_histogram.dart';

/// How palette entries are ordered. Translucent entries always come first,
/// so the tRNS chunk can stop at the last of them.
enum PaletteOrder {
  /// Most used first: small indices dominate the data.
  frequency,

  /// By luma: neighbouring indices hold similar colours, which helps the
  /// Sub/Up/Paeth filters.
  luma,

  /// A nearest-neighbour chain from the most used colour: each entry is the
  /// closest unused colour to the previous one.
  neighbour,
}

/// The colours of [histogram] (at most 256) in [order].
List<int> orderPalette(ColorHistogram histogram, PaletteOrder order) {
  final translucent = <int>[];
  final opaque = <int>[];
  for (final c in histogram.colors) {
    (alphaOf(c) == 255 ? opaque : translucent).add(c);
  }
  switch (order) {
    case PaletteOrder.frequency:
      // The histogram is already most-used first.
      break;
    case PaletteOrder.luma:
      int byLuma(int x, int y) {
        final d = lumaOf(x).compareTo(lumaOf(y));
        return d != 0 ? d : x.compareTo(y);
      }
      translucent.sort((x, y) {
        final d = alphaOf(x).compareTo(alphaOf(y));
        return d != 0 ? d : byLuma(x, y);
      });
      opaque.sort(byLuma);
    case PaletteOrder.neighbour:
      _chain(opaque);
  }
  return [...translucent, ...opaque];
}

/// Reorders [colors] in place into a nearest-neighbour chain starting at the
/// first (most used) one; ties go to the earlier (more used) colour.
void _chain(List<int> colors) {
  for (var i = 1; i < colors.length; i++) {
    final prev = colors[i - 1];
    var best = i;
    var bestDistance = colorDistance(prev, colors[i]);
    for (var j = i + 1; j < colors.length; j++) {
      final d = colorDistance(prev, colors[j]);
      if (d < bestDistance) {
        best = j;
        bestDistance = d;
      }
    }
    if (best != i) {
      final c = colors.removeAt(best);
      colors.insert(i, c);
    }
  }
}
