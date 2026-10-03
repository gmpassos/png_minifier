import 'dart:typed_data';

import 'png_exception.dart';

/// How the encoder picks the PNG filter of each scanline.
enum PngFilterStrategy {
  /// Filter type 0 on every row.
  none,

  /// Filter type 1 (Sub) on every row.
  sub,

  /// Filter type 2 (Up) on every row.
  up,

  /// Filter type 3 (Average) on every row.
  average,

  /// Filter type 4 (Paeth) on every row.
  paeth,

  /// Per row, the filter with the minimum sum of absolute (signed) bytes —
  /// the heuristic recommended by the PNG specification.
  minSum,

  /// Per row, the filter whose bytes repeat the most (the largest sum of
  /// squared byte counts, a Rényi-entropy proxy computed in integers so the
  /// choice is identical on every platform).
  entropy;

  /// The fixed filter type of a single-type strategy, or null for the
  /// adaptive ones.
  int? get fixedType => index <= 4 ? index : null;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

/// Writes [row] filtered with [type] into [out] (same length as [row]).
void _filterRow(
  int type,
  Uint8List row,
  Uint8List? prior,
  int bpp,
  Uint8List out,
) {
  final n = row.length;
  switch (type) {
    case 0:
      out.setAll(0, row);
    case 1:
      for (var i = 0; i < n; i++) {
        final a = i >= bpp ? row[i - bpp] : 0;
        out[i] = (row[i] - a) & 0xff;
      }
    case 2:
      for (var i = 0; i < n; i++) {
        final b = prior == null ? 0 : prior[i];
        out[i] = (row[i] - b) & 0xff;
      }
    case 3:
      for (var i = 0; i < n; i++) {
        final a = i >= bpp ? row[i - bpp] : 0;
        final b = prior == null ? 0 : prior[i];
        out[i] = (row[i] - ((a + b) >> 1)) & 0xff;
      }
    default:
      for (var i = 0; i < n; i++) {
        final a = i >= bpp ? row[i - bpp] : 0;
        final b = prior == null ? 0 : prior[i];
        final c = prior != null && i >= bpp ? prior[i - bpp] : 0;
        out[i] = (row[i] - _paeth(a, b, c)) & 0xff;
      }
  }
}

int _minSumScore(Uint8List bytes) {
  var sum = 0;
  for (final v in bytes) {
    sum += v < 128 ? v : 256 - v;
  }
  return sum;
}

/// Lower is better, like [_minSumScore]: the negated sum of squared counts.
int _entropyScore(Uint8List bytes, Int32List counts) {
  counts.fillRange(0, 256, 0);
  for (final v in bytes) {
    counts[v]++;
  }
  var sum = 0;
  for (final c in counts) {
    sum += c * c;
  }
  return -sum;
}

/// Filters [height] unfiltered scanlines of [rowBytes] bytes each in [data],
/// returning the PNG IDAT payload (a filter-type byte before every row).
/// [bpp] is the number of bytes per complete pixel, rounded up to 1.
Uint8List filterScanlines(
  Uint8List data,
  int rowBytes,
  int height,
  int bpp,
  PngFilterStrategy strategy,
) {
  final out = Uint8List((rowBytes + 1) * height);
  final fixed = strategy.fixedType;
  final candidates = fixed == null
      ? List.generate(5, (_) => Uint8List(rowBytes))
      : null;
  final counts = Int32List(256);
  Uint8List? prior;
  for (var y = 0; y < height; y++) {
    final row = Uint8List.sublistView(data, y * rowBytes, (y + 1) * rowBytes);
    final dst = Uint8List.sublistView(
      out,
      y * (rowBytes + 1) + 1,
      (y + 1) * (rowBytes + 1),
    );
    if (fixed != null) {
      out[y * (rowBytes + 1)] = fixed;
      _filterRow(fixed, row, prior, bpp, dst);
    } else {
      var bestType = 0;
      var bestScore = 0;
      for (var t = 0; t < 5; t++) {
        final buf = candidates![t];
        _filterRow(t, row, prior, bpp, buf);
        final score = strategy == PngFilterStrategy.minSum
            ? _minSumScore(buf)
            : _entropyScore(buf, counts);
        if (t == 0 || score < bestScore) {
          bestType = t;
          bestScore = score;
        }
      }
      out[y * (rowBytes + 1)] = bestType;
      dst.setAll(0, candidates![bestType]);
    }
    prior = row;
  }
  return out;
}

/// Reverses [filterScanlines]: reads [height] filtered rows of [rowBytes]
/// bytes (plus their filter byte) from [data] starting at [offset] and
/// returns the unfiltered rows.
Uint8List unfilterScanlines(
  Uint8List data,
  int rowBytes,
  int height,
  int bpp, {
  int offset = 0,
}) {
  final needed = (rowBytes + 1) * height;
  if (offset + needed > data.length) {
    throw const PngFormatException('image data too short');
  }
  final out = Uint8List(rowBytes * height);
  for (var y = 0; y < height; y++) {
    final src = offset + y * (rowBytes + 1);
    final type = data[src];
    final o = y * rowBytes;
    final p = o - rowBytes;
    final hasPrior = y > 0;
    switch (type) {
      case 0:
        for (var i = 0; i < rowBytes; i++) {
          out[o + i] = data[src + 1 + i];
        }
      case 1:
        for (var i = 0; i < rowBytes; i++) {
          final a = i >= bpp ? out[o + i - bpp] : 0;
          out[o + i] = (data[src + 1 + i] + a) & 0xff;
        }
      case 2:
        for (var i = 0; i < rowBytes; i++) {
          final b = hasPrior ? out[p + i] : 0;
          out[o + i] = (data[src + 1 + i] + b) & 0xff;
        }
      case 3:
        for (var i = 0; i < rowBytes; i++) {
          final a = i >= bpp ? out[o + i - bpp] : 0;
          final b = hasPrior ? out[p + i] : 0;
          out[o + i] = (data[src + 1 + i] + ((a + b) >> 1)) & 0xff;
        }
      case 4:
        for (var i = 0; i < rowBytes; i++) {
          final a = i >= bpp ? out[o + i - bpp] : 0;
          final b = hasPrior ? out[p + i] : 0;
          final c = hasPrior && i >= bpp ? out[p + i - bpp] : 0;
          out[o + i] = (data[src + 1 + i] + _paeth(a, b, c)) & 0xff;
        }
      default:
        throw PngFormatException('invalid filter type $type');
    }
  }
  return out;
}
