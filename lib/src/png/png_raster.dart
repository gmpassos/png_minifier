import 'dart:typed_data';

/// PNG colour types (the IHDR `colour type` byte).
abstract final class PngColorType {
  /// Greyscale.
  static const int grey = 0;

  /// RGB triples.
  static const int rgb = 2;

  /// Palette indices.
  static const int indexed = 3;

  /// Greyscale with alpha.
  static const int greyAlpha = 4;

  /// RGBA.
  static const int rgba = 6;

  /// Samples per pixel of [colorType].
  static int channels(int colorType) => switch (colorType) {
    grey || indexed => 1,
    greyAlpha => 2,
    rgb => 3,
    rgba => 4,
    _ => throw ArgumentError.value(colorType, 'colorType'),
  };

  /// The bit depths the PNG specification allows for [colorType].
  static List<int> bitDepths(int colorType) => switch (colorType) {
    grey => const [1, 2, 4, 8, 16],
    indexed => const [1, 2, 4, 8],
    rgb || greyAlpha || rgba => const [8, 16],
    _ => const [],
  };

  /// A short name: `grey`, `rgb`, `palette`, `grey+alpha`, `rgba`.
  static String name(int colorType) => switch (colorType) {
    grey => 'grey',
    rgb => 'rgb',
    indexed => 'palette',
    greyAlpha => 'grey+alpha',
    rgba => 'rgba',
    _ => 'unknown',
  };
}

/// Image data in one PNG representation, ready to filter and compress: the
/// packed, unfiltered scanlines plus the palette and transparency chunks.
class PngRaster {
  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// One of [PngColorType].
  final int colorType;

  /// Bits per sample.
  final int bitDepth;

  /// `height` rows of [rowBytes] bytes, samples packed big-endian.
  final Uint8List data;

  /// PLTE payload (RGB triples) for [PngColorType.indexed].
  final Uint8List? palette;

  /// tRNS payload, if any.
  final Uint8List? transparency;

  /// A short note for reports, e.g. the palette order.
  final String? note;

  /// Creates a raster, checking that [data] has the right length.
  PngRaster({
    required this.width,
    required this.height,
    required this.colorType,
    required this.bitDepth,
    required this.data,
    this.palette,
    this.transparency,
    this.note,
  }) {
    if (!PngColorType.bitDepths(colorType).contains(bitDepth)) {
      throw ArgumentError(
        'bit depth $bitDepth invalid for colour type '
        '$colorType',
      );
    }
    if (data.length != rowBytes * height) {
      throw ArgumentError(
        'raster data is ${data.length} bytes, expected '
        '${rowBytes * height}',
      );
    }
    if (colorType == PngColorType.indexed && palette == null) {
      throw ArgumentError('an indexed raster needs a palette');
    }
  }

  /// Bytes per unfiltered scanline.
  int get rowBytes => rowBytesOf(width, colorType, bitDepth);

  /// Bytes per complete pixel, rounded up to 1 (the filter distance).
  int get filterBpp => filterBppOf(colorType, bitDepth);

  /// Bytes in an unfiltered scanline of [width] pixels.
  static int rowBytesOf(int width, int colorType, int bitDepth) =>
      (width * PngColorType.channels(colorType) * bitDepth + 7) >> 3;

  /// The filter distance for [colorType] at [bitDepth].
  static int filterBppOf(int colorType, int bitDepth) {
    final bits = PngColorType.channels(colorType) * bitDepth;
    return bits < 8 ? 1 : bits >> 3;
  }

  /// A label like `palette4(luma)`, `rgb8+key` or `rgba8`.
  String get label =>
      '${PngColorType.name(colorType)}$bitDepth'
      '${transparency != null && colorType != PngColorType.indexed ? '+key' : ''}'
      '${note != null ? '($note)' : ''}';
}
