import 'dart:typed_data';

/// Decoded pixels: 8-bit RGBA, plus the 16-bit samples when the source had
/// precision that 8 bits cannot hold.
class PngImage {
  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Row-major RGBA, 4 bytes per pixel, not premultiplied.
  final Uint8List pixels;

  /// Row-major 16-bit RGBA, or null when every sample fits 8 bits exactly
  /// (the common case, including 16-bit files whose samples are `v * 257`).
  final Uint16List? pixels16;

  /// Creates an image over [pixels] (`width * height * 4` bytes).
  PngImage(this.width, this.height, this.pixels, {this.pixels16}) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('image size must be positive: ${width}x$height');
    }
    if (pixels.length != width * height * 4) {
      throw ArgumentError(
        'pixels is ${pixels.length} bytes, expected ${width * height * 4}',
      );
    }
    final p16 = pixels16;
    if (p16 != null && p16.length != width * height * 4) {
      throw ArgumentError(
        'pixels16 is ${p16.length} samples, expected ${width * height * 4}',
      );
    }
  }

  /// An image from 32-bit ARGB words (`0xAARRGGBB`), as Canvas and many game
  /// engines hold them.
  factory PngImage.fromArgb(int width, int height, List<int> argb) {
    if (argb.length != width * height) {
      throw ArgumentError(
        'argb has ${argb.length} pixels, expected ${width * height}',
      );
    }
    final pixels = Uint8List(width * height * 4);
    for (var i = 0; i < argb.length; i++) {
      final c = argb[i];
      pixels[i * 4] = (c >> 16) & 0xff;
      pixels[i * 4 + 1] = (c >> 8) & 0xff;
      pixels[i * 4 + 2] = c & 0xff;
      pixels[i * 4 + 3] = (c >> 24) & 0xff;
    }
    return PngImage(width, height, pixels);
  }

  /// Number of pixels.
  int get pixelCount => width * height;

  /// True when the image carries 16-bit precision ([pixels16] is set).
  bool get isDeep => pixels16 != null;

  /// Whether [other] shows the same pixels: same size and RGBA, except that
  /// fully transparent pixels match whatever their colour unless
  /// [compareTransparentColor].
  bool sameAs(PngImage other, {bool compareTransparentColor = false}) {
    if (width != other.width || height != other.height) return false;
    final a = pixels;
    final b = other.pixels;
    for (var i = 0; i < a.length; i += 4) {
      if (a[i + 3] != b[i + 3]) return false;
      if (a[i + 3] == 0 && !compareTransparentColor) continue;
      if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
        return false;
      }
    }
    final a16 = pixels16;
    final b16 = other.pixels16;
    if (a16 == null && b16 == null) return true;
    if (a16 == null || b16 == null) return false;
    for (var i = 0; i < a16.length; i += 4) {
      if (a16[i + 3] != b16[i + 3]) return false;
      if (a16[i + 3] == 0 && !compareTransparentColor) continue;
      if (a16[i] != b16[i] ||
          a16[i + 1] != b16[i + 1] ||
          a16[i + 2] != b16[i + 2]) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => 'PngImage(${width}x$height${isDeep ? ', 16-bit' : ''})';
}
