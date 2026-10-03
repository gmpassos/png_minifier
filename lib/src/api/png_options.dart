import 'png_quality.dart';

/// How hard to search: more candidates, smaller files, more time.
enum PngEffort {
  /// One representation (the smallest raw one), one filter heuristic,
  /// deflate level 9.
  fast,

  /// Every applicable representation, a few filter strategies.
  balanced,

  /// Every representation, palette order and filter strategy, and several
  /// deflate levels.
  max,
}

/// What to do with metadata chunks.
enum PngMetadata {
  /// Drop every ancillary chunk.
  strip,

  /// Keep the chunks that change how colours display (gAMA, cHRM, sRGB,
  /// iCCP, cICP, mDCV, cLLI) and drop the rest. The default.
  color,

  /// Keep every ancillary chunk that stays valid, including text, time,
  /// physical size and EXIF.
  all,
}

/// The optimisation strategies the minifier can combine. Lossless ones run
/// at every quality; lossy ones only when the quality allows changes, and
/// their output is checked against it.
enum PngStrategy {
  /// Give fully transparent pixels one colour (lossless: they are
  /// invisible) so they share a palette entry or a colour key.
  transparentCleanup(true),

  /// RGB, greyscale at 1/2/4/8 bits, grey+alpha and colour-key
  /// transparency instead of RGBA when the image allows it.
  colorTypeReduction(true),

  /// An indexed (PLTE) image at 1/2/4/8 bits when there are at most 256
  /// colours.
  palette(true),

  /// Try several palette orders (by use, by luma, a nearest-neighbour
  /// chain).
  paletteOrdering(true),

  /// Try several PNG filter strategies per representation.
  filterSearch(true),

  /// Try several deflate levels for the best filter.
  deflateSearch(true),

  /// Keep the most used colours, map rare ones to a kept colour within the
  /// error bound (the pixel-art quantiser).
  frequencyPalette(false),

  /// Weighted median-cut palette, with the error bound guarded.
  medianCutPalette(false),

  /// Median cut refined by k-means, with the error bound guarded.
  kMeansPalette(false),

  /// Floyd–Steinberg dithering onto the quantised palette, each pixel kept
  /// within the error bound.
  dithering(false),

  /// Round colour channels to fewer levels within the error bound.
  posterize(false),

  /// Make nearly transparent pixels transparent and nearly opaque ones
  /// opaque.
  alphaSnap(false);

  /// Whether the strategy never changes visible pixels.
  final bool isLossless;

  const PngStrategy(this.isLossless);

  /// The strategies an [effort] uses by default.
  static Set<PngStrategy> defaultsFor(PngEffort effort) => switch (effort) {
    PngEffort.fast => const {
      transparentCleanup,
      colorTypeReduction,
      palette,
      frequencyPalette,
      alphaSnap,
    },
    PngEffort.balanced => const {
      transparentCleanup,
      colorTypeReduction,
      palette,
      filterSearch,
      frequencyPalette,
      medianCutPalette,
      alphaSnap,
    },
    PngEffort.max => values.toSet(),
  };

  /// Parses a CLI-style name (`frequency-palette` or `frequencyPalette`).
  static PngStrategy parse(String name) {
    final key = name.replaceAll('-', '').replaceAll('_', '').toLowerCase();
    for (final s in values) {
      if (s.name.toLowerCase() == key) return s;
    }
    throw FormatException('unknown strategy "$name"');
  }
}

/// Everything that steers a minification. See also `PngPreset`.
class PngMinifyOptions {
  /// The quality the output must keep. Default: lossless.
  final PngQuality quality;

  /// How hard to search. Default: balanced.
  final PngEffort effort;

  /// The strategies to use; null means [PngStrategy.defaultsFor] [effort].
  final Set<PngStrategy>? strategies;

  /// Palette size limit for the lossy palette strategies (2–256).
  final int maxColors;

  /// Metadata handling. Default: [PngMetadata.color].
  final PngMetadata metadata;

  /// Keep the RGB of fully transparent pixels (normally free to change, as
  /// it is invisible — unless the image is later used with that colour).
  final bool preserveTransparentColor;

  /// Decode the winning candidate and check it against the expected pixels
  /// before returning it (on by default; a guard against encoder bugs).
  final bool verify;

  /// Creates options. Every argument has a safe default.
  const PngMinifyOptions({
    this.quality = const PngQuality.lossless(),
    this.effort = PngEffort.balanced,
    this.strategies,
    this.maxColors = 256,
    this.metadata = PngMetadata.color,
    this.preserveTransparentColor = false,
    this.verify = true,
  }) : assert(maxColors >= 2 && maxColors <= 256);

  /// The strategies in effect.
  Set<PngStrategy> get activeStrategies =>
      strategies ?? PngStrategy.defaultsFor(effort);

  /// Whether [strategy] is in effect.
  bool uses(PngStrategy strategy) => activeStrategies.contains(strategy);

  /// A copy with the given fields replaced.
  PngMinifyOptions copyWith({
    PngQuality? quality,
    PngEffort? effort,
    Set<PngStrategy>? strategies,
    int? maxColors,
    PngMetadata? metadata,
    bool? preserveTransparentColor,
    bool? verify,
  }) => PngMinifyOptions(
    quality: quality ?? this.quality,
    effort: effort ?? this.effort,
    strategies: strategies ?? this.strategies,
    maxColors: maxColors ?? this.maxColors,
    metadata: metadata ?? this.metadata,
    preserveTransparentColor:
        preserveTransparentColor ?? this.preserveTransparentColor,
    verify: verify ?? this.verify,
  );

  @override
  String toString() =>
      'PngMinifyOptions(quality: $quality, effort: ${effort.name}, '
      'strategies: ${strategies == null ? 'default' : strategies!.map((s) => s.name).join(',')}, '
      'maxColors: $maxColors, metadata: ${metadata.name}'
      '${preserveTransparentColor ? ', preserveTransparentColor' : ''})';
}
