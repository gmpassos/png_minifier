import 'dart:typed_data';

import '../image/color.dart';
import '../image/color_histogram.dart';
import '../image/png_image.dart';
import '../png/png_raster.dart';
import 'palette_order.dart';

/// Builds the PNG representations that hold [image] exactly.
///
/// RGBA (or 16-bit RGBA for a deep image) is always included. With
/// [reduceColorType]: RGB, greyscale at the smallest exact bit depth,
/// grey+alpha, and colour-key transparency (tRNS) when alpha is only 0/255.
/// With [palette]: an indexed raster per [orders] when the image has at most
/// 256 colours, at the smallest bit depth that indexes them.
///
/// Fully transparent pixels keep their colour only when
/// [preserveTransparentColor]; otherwise a colour key may stand for them.
/// The list is sorted by raw (uncompressed) size, smallest first.
List<PngRaster> buildRepresentations(
  PngImage image,
  ColorHistogram histogram, {
  bool reduceColorType = true,
  bool palette = true,
  Set<PaletteOrder> orders = const {PaletteOrder.frequency},
  bool preserveTransparentColor = false,
}) {
  final rasters = <PngRaster>[];
  if (image.isDeep) {
    rasters.addAll(_deep(image, reduceColorType));
  } else {
    if (palette && histogram.length <= 256) {
      for (final order in PaletteOrder.values) {
        if (orders.contains(order)) {
          rasters.add(
            _indexed(image, orderPalette(histogram, order), order.name),
          );
        }
      }
    }
    if (reduceColorType) {
      rasters.addAll(_reduced(image, histogram, preserveTransparentColor));
    }
    rasters.add(_pack(image, PngColorType.rgba, 8, null));
  }
  // Stable sort: equal sizes keep the order above.
  final indexed = [for (var i = 0; i < rasters.length; i++) i];
  indexed.sort((x, y) {
    final d = _rawSize(rasters[x]).compareTo(_rawSize(rasters[y]));
    return d != 0 ? d : x.compareTo(y);
  });
  return [for (final i in indexed) rasters[i]];
}

int _rawSize(PngRaster r) =>
    r.data.length +
    (r.palette?.length ?? 0) +
    (r.transparency?.length ?? 0) +
    r.height;

int _paletteDepth(int n) => n <= 2
    ? 1
    : n <= 4
    ? 2
    : n <= 16
    ? 4
    : 8;

PngRaster _indexed(PngImage image, List<int> palette, String note) {
  final index = <int, int>{
    for (var i = 0; i < palette.length; i++) palette[i]: i,
  };
  final plte = Uint8List(palette.length * 3);
  var translucent = 0;
  for (var i = 0; i < palette.length; i++) {
    final c = palette[i];
    plte[i * 3] = redOf(c);
    plte[i * 3 + 1] = greenOf(c);
    plte[i * 3 + 2] = blueOf(c);
    if (alphaOf(c) != 255) translucent = i + 1;
  }
  final px = image.pixels;
  final samples = Uint8List(image.pixelCount);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = index[colorAt(px, i)]!;
  }
  final depth = _paletteDepth(palette.length);
  return PngRaster(
    width: image.width,
    height: image.height,
    colorType: PngColorType.indexed,
    bitDepth: depth,
    data: _packSingle(samples, image.width, image.height, depth),
    palette: plte,
    note: note,
    transparency: translucent == 0
        ? null
        : Uint8List.fromList([
            for (var i = 0; i < translucent; i++) alphaOf(palette[i]),
          ]),
  );
}

/// Packs one sample per pixel at [depth] bits, rows padded to a byte.
Uint8List _packSingle(Uint8List samples, int width, int height, int depth) {
  if (depth == 8) return samples;
  final rowBytes = (width * depth + 7) >> 3;
  final out = Uint8List(rowBytes * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final bit = x * depth;
      out[y * rowBytes + (bit >> 3)] |=
          samples[y * width + x] << (8 - depth - (bit & 7));
    }
  }
  return out;
}

List<PngRaster> _reduced(
  PngImage image,
  ColorHistogram histogram,
  bool preserveTransparentColor,
) {
  final out = <PngRaster>[];
  final hasTransparent = !histogram.opaque && histogram.binaryAlpha;

  // The single colour transparent pixels may share, when a key must
  // reproduce it exactly.
  int? transparentColor;
  if (hasTransparent) {
    final transparent = histogram.colors.where((c) => alphaOf(c) == 0);
    if (transparent.length == 1) transparentColor = transparent.first;
  }
  final keyNeedsColor = preserveTransparentColor;
  if (keyNeedsColor && hasTransparent && transparentColor == null) {
    // Several transparent colours: no single key can keep them all.
    return _reducedNoKey(image, histogram, out);
  }

  if (histogram.grey) {
    // Grey values of the visible pixels.
    final used = <int>{
      for (final c in histogram.colors)
        if (alphaOf(c) == 255) redOf(c),
    };
    if (histogram.opaque) {
      final depth = _greyDepth(used);
      out.add(_grey(image, depth, null));
    } else if (hasTransparent) {
      for (final depth in const [1, 2, 4, 8]) {
        if (_greyDepth(used) > depth) continue;
        final scale = 255 ~/ ((1 << depth) - 1);
        int? key;
        if (keyNeedsColor) {
          final g = redOf(transparentColor!);
          if (g % scale == 0 && !used.contains(g)) key = g;
        } else {
          for (var v = 0; v < (1 << depth); v++) {
            if (!used.contains(v * scale)) {
              key = v * scale;
              break;
            }
          }
        }
        if (key != null) {
          out.add(_grey(image, depth, key));
          break;
        }
      }
      out.add(_pack(image, PngColorType.greyAlpha, 8, null));
    } else {
      out.add(_pack(image, PngColorType.greyAlpha, 8, null));
    }
  }

  if (histogram.opaque) {
    out.add(_pack(image, PngColorType.rgb, 8, null));
  } else if (hasTransparent) {
    final used = <int>{
      for (final c in histogram.colors)
        if (alphaOf(c) == 255) c ~/ 256,
    };
    int? key;
    if (keyNeedsColor) {
      final rgb = transparentColor! ~/ 256;
      if (!used.contains(rgb)) key = rgb;
    } else {
      for (var v = 0; v <= used.length; v++) {
        if (!used.contains(v)) {
          key = v;
          break;
        }
      }
    }
    if (key != null) out.add(_pack(image, PngColorType.rgb, 8, key));
  }
  return out;
}

List<PngRaster> _reducedNoKey(
  PngImage image,
  ColorHistogram histogram,
  List<PngRaster> out,
) {
  if (histogram.grey) out.add(_pack(image, PngColorType.greyAlpha, 8, null));
  return out;
}

/// The smallest grey bit depth holding every value of [used] exactly.
int _greyDepth(Set<int> used) {
  if (used.every((g) => g == 0 || g == 255)) return 1;
  if (used.every((g) => g % 85 == 0)) return 2;
  if (used.every((g) => g % 17 == 0)) return 4;
  return 8;
}

PngRaster _grey(PngImage image, int depth, int? key) {
  final scale = 255 ~/ ((1 << depth) - 1);
  final px = image.pixels;
  final samples = Uint8List(image.pixelCount);
  for (var i = 0; i < samples.length; i++) {
    final g = px[i * 4 + 3] == 0 && key != null ? key : px[i * 4];
    samples[i] = g ~/ scale;
  }
  return PngRaster(
    width: image.width,
    height: image.height,
    colorType: PngColorType.grey,
    bitDepth: depth,
    data: _packSingle(samples, image.width, image.height, depth),
    transparency: key == null ? null : Uint8List.fromList([0, key ~/ scale]),
  );
}

/// An 8-bit RGB, grey+alpha or RGBA raster. For RGB, [key] is the packed RGB
/// written for transparent pixels and declared in tRNS.
PngRaster _pack(PngImage image, int colorType, int bitDepth, int? key) {
  final px = image.pixels;
  final n = image.pixelCount;
  final channels = PngColorType.channels(colorType);
  final data = Uint8List(n * channels);
  switch (colorType) {
    case PngColorType.rgb:
      for (var i = 0; i < n; i++) {
        if (key != null && px[i * 4 + 3] == 0) {
          data[i * 3] = (key >> 16) & 0xff;
          data[i * 3 + 1] = (key >> 8) & 0xff;
          data[i * 3 + 2] = key & 0xff;
        } else {
          data[i * 3] = px[i * 4];
          data[i * 3 + 1] = px[i * 4 + 1];
          data[i * 3 + 2] = px[i * 4 + 2];
        }
      }
    case PngColorType.greyAlpha:
      for (var i = 0; i < n; i++) {
        data[i * 2] = px[i * 4];
        data[i * 2 + 1] = px[i * 4 + 3];
      }
    default:
      data.setAll(0, px);
  }
  return PngRaster(
    width: image.width,
    height: image.height,
    colorType: colorType,
    bitDepth: bitDepth,
    data: data,
    transparency: key == null
        ? null
        : Uint8List.fromList([
            0,
            (key >> 16) & 0xff,
            0,
            (key >> 8) & 0xff,
            0,
            key & 0xff,
          ]),
  );
}

List<PngRaster> _deep(PngImage image, bool reduceColorType) {
  final s = image.pixels16!;
  final n = image.pixelCount;
  var opaque = true;
  var grey = true;
  for (var i = 0; i < n; i++) {
    final o = i * 4;
    if (s[o + 3] != 0xffff) opaque = false;
    if (s[o] != s[o + 1] || s[o] != s[o + 2]) grey = false;
  }
  final out = <PngRaster>[];
  void add(int colorType, List<int> channels) {
    final data = Uint8List(n * channels.length * 2);
    var j = 0;
    for (var i = 0; i < n; i++) {
      for (final c in channels) {
        final v = s[i * 4 + c];
        data[j++] = v >> 8;
        data[j++] = v & 0xff;
      }
    }
    out.add(
      PngRaster(
        width: image.width,
        height: image.height,
        colorType: colorType,
        bitDepth: 16,
        data: data,
      ),
    );
  }

  if (reduceColorType) {
    if (grey && opaque) add(PngColorType.grey, const [0]);
    if (grey) add(PngColorType.greyAlpha, const [0, 3]);
    if (opaque) add(PngColorType.rgb, const [0, 1, 2]);
  }
  add(PngColorType.rgba, const [0, 1, 2, 3]);
  return out;
}
