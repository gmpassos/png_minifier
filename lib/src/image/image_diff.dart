import 'dart:math' as math;

import 'color.dart';
import 'png_image.dart';

/// How far a candidate image is from the original, in the visible
/// (premultiplied) terms of [colorError].
class ImageDiff {
  /// Pixels whose visible colour changed.
  final int changedPixels;

  /// The largest [colorError] of any pixel (0–255).
  final int maxError;

  /// Sum over pixels of [colorSquaredError] (an exact integer).
  final int squaredError;

  /// Pixels compared.
  final int pixelCount;

  /// Creates a diff.
  const ImageDiff({
    required this.changedPixels,
    required this.maxError,
    required this.squaredError,
    required this.pixelCount,
  });

  /// Compares [candidate] against [reference] (same size).
  factory ImageDiff.of(PngImage reference, PngImage candidate) {
    if (reference.width != candidate.width ||
        reference.height != candidate.height) {
      throw ArgumentError('images differ in size');
    }
    final a = reference.pixels;
    final b = candidate.pixels;
    var changed = 0;
    var maxError = 0;
    var sse = 0;
    for (var i = 0; i < reference.pixelCount; i++) {
      final ca = colorAt(a, i);
      final cb = colorAt(b, i);
      if (ca == cb) continue;
      final e = colorError(ca, cb);
      if (e == 0) continue;
      changed++;
      if (e > maxError) maxError = e;
      sse += colorSquaredError(ca, cb);
    }
    return ImageDiff(
      changedPixels: changed,
      maxError: maxError,
      squaredError: sse,
      pixelCount: reference.pixelCount,
    );
  }

  /// Peak signal-to-noise ratio in dB over the four channels;
  /// [double.infinity] when nothing visible changed.
  double get psnr {
    if (squaredError == 0) return double.infinity;
    final mse = squaredError / (pixelCount * 4);
    return 10 * math.log(255 * 255 / mse) / math.ln10;
  }

  /// Whether [psnr] is at least [minPsnr], decided without logarithms (so
  /// the answer cannot differ between platforms by a rounding ulp).
  bool psnrAtLeast(double minPsnr) {
    if (squaredError == 0) return true;
    final maxSse = pixelCount * 4 * 255 * 255 / math.pow(10, minPsnr / 10);
    return squaredError <= maxSse;
  }
}
