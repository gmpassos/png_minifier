import '../image/color.dart';
import '../image/color_histogram.dart';
import 'palette_mapper.dart';

int _channel(int c, int ch) => switch (ch) {
  0 => redOf(c),
  1 => greenOf(c),
  2 => blueOf(c),
  _ => alphaOf(c),
};

class _Box {
  final List<int> items; // indices into the histogram
  _Box(this.items);
}

/// Up to [count] colours by weighted median cut over [histogram]: the box
/// with the widest channel range is split at its weighted median until there
/// are [count] boxes; each box contributes its weighted mean.
List<int> medianCut(ColorHistogram histogram, int count) {
  final colors = histogram.colors;
  final counts = histogram.counts;
  if (colors.length <= count) return List.of(colors);
  final boxes = [
    _Box([for (var i = 0; i < colors.length; i++) i]),
  ];

  (int, int) widest(_Box box) {
    var bestChannel = 0;
    var bestRange = -1;
    for (var ch = 0; ch < 4; ch++) {
      var lo = 255, hi = 0;
      for (final i in box.items) {
        final v = _channel(colors[i], ch);
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      if (hi - lo > bestRange) {
        bestRange = hi - lo;
        bestChannel = ch;
      }
    }
    return (bestChannel, bestRange);
  }

  while (boxes.length < count) {
    var pick = -1;
    var pickRange = 0;
    var pickChannel = 0;
    for (var b = 0; b < boxes.length; b++) {
      if (boxes[b].items.length < 2) continue;
      final (ch, range) = widest(boxes[b]);
      if (range > pickRange) {
        pick = b;
        pickRange = range;
        pickChannel = ch;
      }
    }
    if (pick < 0) break;
    final items = boxes[pick].items
      ..sort((x, y) {
        final d = _channel(
          colors[x],
          pickChannel,
        ).compareTo(_channel(colors[y], pickChannel));
        return d != 0 ? d : colors[x].compareTo(colors[y]);
      });
    var total = 0;
    for (final i in items) {
      total += counts[i];
    }
    var acc = 0;
    var cut = 1;
    for (var k = 0; k < items.length - 1; k++) {
      acc += counts[items[k]];
      cut = k + 1;
      if (acc * 2 >= total) break;
    }
    boxes[pick] = _Box(items.sublist(0, cut));
    boxes.add(_Box(items.sublist(cut)));
  }
  return [for (final box in boxes) _mean(colors, counts, box.items)];
}

int _mean(List<int> colors, List<int> counts, Iterable<int> items) {
  var w = 0, r = 0, g = 0, b = 0, a = 0;
  for (final i in items) {
    final n = counts[i];
    final c = colors[i];
    w += n;
    r += redOf(c) * n;
    g += greenOf(c) * n;
    b += blueOf(c) * n;
    a += alphaOf(c) * n;
  }
  final h = w ~/ 2;
  final alpha = (a + h) ~/ w;
  // A box of fully transparent colours stays fully transparent black.
  if (alpha == 0) return 0;
  return packRgba((r + h) ~/ w, (g + h) ~/ w, (b + h) ~/ w, alpha);
}

/// Refines [palette] with [iterations] rounds of weighted k-means (Lloyd):
/// every colour joins its nearest entry, every entry moves to its members'
/// weighted mean. Entries that lose all members are kept unchanged.
List<int> kMeansRefine(
  ColorHistogram histogram,
  List<int> palette, {
  int iterations = 3,
}) {
  var current = List.of(palette);
  for (var it = 0; it < iterations; it++) {
    final index = PaletteIndex(current);
    final members = List.generate(current.length, (_) => <int>[]);
    for (var i = 0; i < histogram.length; i++) {
      members[index.nearest(histogram.colors[i], 255)].add(i);
    }
    final next = [
      for (var e = 0; e < current.length; e++)
        members[e].isEmpty
            ? current[e]
            : _mean(histogram.colors, histogram.counts, members[e]),
    ];
    var same = true;
    for (var e = 0; e < next.length; e++) {
      if (next[e] != current[e]) same = false;
    }
    current = next;
    if (same) break;
  }
  // Two entries may have converged on the same colour.
  return current.toSet().toList();
}

/// A palette of at most [maxColors] entries that keeps every colour of
/// [histogram] within [maxError]: [build] proposes `n` entries, and colours
/// it leaves out of range are added exactly, shrinking `n` to make room.
/// Null when no split fits.
PaletteIndex? guardedPalette(
  ColorHistogram histogram,
  List<int> Function(int n) build, {
  required int maxColors,
  required int maxError,
}) {
  var n = maxColors;
  for (var attempt = 0; attempt < 5 && n > 0; attempt++) {
    final palette = PaletteIndex(build(n));
    if (coverRemaining(histogram, palette, maxColors, maxError)) {
      return palette;
    }
    // Count what still needs an exact entry and leave that many slots.
    final probe = PaletteIndex(palette.entries.take(n));
    var needed = 0;
    for (final c in histogram.colors) {
      if (!probe.covers(c, maxError)) {
        probe.add(c);
        needed++;
      }
    }
    final next = maxColors - needed;
    if (next >= n) break;
    n = next;
  }
  return null;
}
