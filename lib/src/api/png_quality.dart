/// The quality a minified image must keep.
///
/// The default, [PngQuality.lossless], keeps the decoded pixels identical.
/// The others allow lossy strategies, with errors measured on the visible
/// (premultiplied-alpha) colour, per channel, on the 0–255 scale.
class PngQuality {
  /// The largest change allowed in any channel of any pixel (0 = none).
  final int maxError;

  /// The lowest peak signal-to-noise ratio allowed, in dB (null = no limit).
  final double? minPsnr;

  const PngQuality._(this.maxError, this.minPsnr);

  /// Pixel-identical output (the default).
  const PngQuality.lossless() : this._(0, null);

  /// No channel of any pixel may change by more than [maxError] (1–255).
  const PngQuality.maxError(this.maxError)
    : assert(maxError >= 0 && maxError <= 255),
      minPsnr = null;

  /// The whole image must keep a PSNR of at least [minPsnr] dB; single
  /// pixels may change more.
  const PngQuality.psnr(double this.minPsnr)
    : assert(minPsnr > 0),
      maxError = 255;

  /// Both limits at once.
  const PngQuality.bounded({
    required this.maxError,
    required double this.minPsnr,
  }) : assert(maxError >= 0 && maxError <= 255);

  /// A 0–100 knob, like TinyPNG's: 100 is lossless; below it, the allowed
  /// per-channel error grows by 0.6 per step (80 → 12, 60 → 24, 0 → 60).
  factory PngQuality.level(int level) {
    if (level < 0 || level > 100) {
      throw RangeError.range(level, 0, 100, 'level');
    }
    if (level == 100) return const PngQuality.lossless();
    final e = ((100 - level) * 3 + 2) ~/ 5;
    return PngQuality.maxError(e < 1 ? 1 : e);
  }

  /// Parses `lossless`, `level:80`, `max-error:12`, `psnr:45` or
  /// `max-error:12,psnr:40`.
  factory PngQuality.parse(String spec) {
    final s = spec.trim().toLowerCase();
    if (s == 'lossless') return const PngQuality.lossless();
    int? maxError;
    double? psnr;
    for (final part in s.split(',')) {
      final kv = part.split(':');
      if (kv.length != 2) throw FormatException('bad quality "$spec"');
      final value = kv[1].trim();
      switch (kv[0].trim()) {
        case 'level':
          final level = int.tryParse(value);
          if (level == null || level < 0 || level > 100) {
            throw FormatException('quality level must be 0–100: "$spec"');
          }
          return PngQuality.level(level);
        case 'max-error' || 'maxerror':
          maxError = int.tryParse(value);
          if (maxError == null || maxError < 0 || maxError > 255) {
            throw FormatException('max-error must be 0–255: "$spec"');
          }
        case 'psnr':
          psnr = double.tryParse(value);
          if (psnr == null || psnr <= 0) {
            throw FormatException('psnr must be positive: "$spec"');
          }
        default:
          throw FormatException('bad quality "$spec"');
      }
    }
    if (psnr != null) {
      return PngQuality._(maxError ?? 255, psnr);
    }
    return PngQuality._(maxError!, null);
  }

  /// True when only pixel-identical output is allowed.
  bool get isLossless => maxError == 0 && minPsnr == null;

  @override
  bool operator ==(Object other) =>
      other is PngQuality &&
      other.maxError == maxError &&
      other.minPsnr == minPsnr;

  @override
  int get hashCode => Object.hash(maxError, minPsnr);

  @override
  String toString() {
    if (isLossless) return 'lossless';
    final parts = [
      if (maxError < 255) 'max-error:$maxError',
      if (minPsnr != null) 'psnr:$minPsnr',
    ];
    return parts.join(',');
  }
}
