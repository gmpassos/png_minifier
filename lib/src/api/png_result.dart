import 'dart:typed_data';

/// One encoding the minifier tried.
class PngCandidateReport {
  /// What it was: `<transform>/<representation>/<filter>/z<level>`.
  final String name;

  /// Its size in bytes.
  final int size;

  /// Creates a report line.
  const PngCandidateReport(this.name, this.size);

  /// JSON form.
  Map<String, Object> toJson() => {'name': name, 'size': size};

  @override
  String toString() => '$name: $size';
}

/// The outcome of a minification.
class PngMinifyResult {
  /// The output PNG.
  final Uint8List bytes;

  /// Size of the input PNG — or, for `minifyImage`, of the raw RGBA pixels.
  final int originalSize;

  /// True when the input was returned as is (nothing smaller was found, or
  /// the input is an animated PNG); see [reason].
  final bool unchanged;

  /// Why the input was returned unchanged, if it was.
  final String? reason;

  /// The winning candidate, e.g. `exact/palette8(frequency)/none/z9`.
  final String strategy;

  /// Whether the output decodes to the input's exact pixels (fully
  /// transparent pixels may differ in their invisible colour unless
  /// `preserveTransparentColor`).
  final bool lossless;

  /// Pixels whose visible colour changed.
  final int changedPixels;

  /// The largest per-channel change of any pixel, premultiplied (0–255).
  final int maxChannelError;

  /// Peak signal-to-noise ratio in dB; [double.infinity] when lossless.
  final double psnr;

  /// Image width.
  final int width;

  /// Image height.
  final int height;

  /// Output colour type.
  final int colorType;

  /// Output bit depth.
  final int bitDepth;

  /// Output palette size, for an indexed image.
  final int? paletteSize;

  /// Every candidate tried, in the order tried.
  final List<PngCandidateReport> candidates;

  /// Creates a result.
  const PngMinifyResult({
    required this.bytes,
    required this.originalSize,
    required this.strategy,
    required this.lossless,
    required this.changedPixels,
    required this.maxChannelError,
    required this.psnr,
    required this.width,
    required this.height,
    required this.colorType,
    required this.bitDepth,
    this.paletteSize,
    this.candidates = const [],
    this.unchanged = false,
    this.reason,
  });

  /// Output size in bytes.
  int get size => bytes.length;

  /// Output size over input size (0.5 = half).
  double get ratio => originalSize == 0 ? 1 : size / originalSize;

  /// Bytes saved (negative never happens for `minify`).
  int get savedBytes => originalSize - size;

  /// JSON form (PSNR is null when infinite).
  Map<String, Object?> toJson() => {
    'originalSize': originalSize,
    'size': size,
    'ratio': double.parse(ratio.toStringAsFixed(4)),
    'unchanged': unchanged,
    'reason': ?reason,
    'strategy': strategy,
    'lossless': lossless,
    'changedPixels': changedPixels,
    'maxChannelError': maxChannelError,
    'psnr': psnr.isFinite ? double.parse(psnr.toStringAsFixed(2)) : null,
    'width': width,
    'height': height,
    'colorType': colorType,
    'bitDepth': bitDepth,
    'paletteSize': ?paletteSize,
    'candidates': [for (final c in candidates) c.toJson()],
  };

  @override
  String toString() =>
      'PngMinifyResult($originalSize -> $size bytes, $strategy'
      '${lossless ? ', lossless' : ', max error $maxChannelError'})';
}
