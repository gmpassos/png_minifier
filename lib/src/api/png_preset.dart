import 'png_options.dart';
import 'png_quality.dart';

const _lossless = {
  PngStrategy.transparentCleanup,
  PngStrategy.colorTypeReduction,
  PngStrategy.palette,
  PngStrategy.paletteOrdering,
  PngStrategy.filterSearch,
  PngStrategy.deflateSearch,
};

/// Ready-made option sets for common jobs.
enum PngPreset {
  /// Pixel-identical, balanced search. The default.
  lossless(
    'Pixel-identical output, balanced search (the default).',
    PngMinifyOptions(),
  ),

  /// Pixel-identical, exhaustive search: for release builds and asset bakes.
  losslessMax(
    'Pixel-identical output, exhaustive search (release builds, asset '
    'bakes).',
    PngMinifyOptions(effort: PngEffort.max),
  ),

  /// Pixel-identical, one quick pass: for development loops and big batches.
  fast(
    'Pixel-identical output, one quick pass (dev loops, big batches).',
    PngMinifyOptions(effort: PngEffort.fast),
  ),

  /// TinyPNG-like: quality level 80 (per-channel error ≤ 12).
  web(
    'General web images: quality level 80, per-channel error ≤ 12 '
    '(TinyPNG-like).',
    PngMinifyOptions(quality: PngQuality.maxError(12)),
  ),

  /// Sprites and atlases: popular colours stay exact, rare ones move at
  /// most 12; no dithering.
  pixelArt(
    'Sprites, tiles and atlases: frequency palette, error ≤ 12, no '
    'dithering.',
    PngMinifyOptions(
      quality: PngQuality.maxError(12),
      effort: PngEffort.max,
      strategies: {
        ..._lossless,
        PngStrategy.frequencyPalette,
        PngStrategy.alphaSnap,
      },
    ),
  ),

  /// Photographs: median cut + k-means + dithering, PSNR ≥ 38 dB (a
  /// 256-colour palette reaches about 39–41 dB on detailed photos).
  photo(
    'Photographs: median cut, k-means and dithering, PSNR ≥ 38 dB.',
    PngMinifyOptions(
      quality: PngQuality.psnr(38),
      strategies: {
        PngStrategy.transparentCleanup,
        PngStrategy.colorTypeReduction,
        PngStrategy.palette,
        PngStrategy.filterSearch,
        PngStrategy.frequencyPalette,
        PngStrategy.medianCutPalette,
        PngStrategy.kMeansPalette,
        PngStrategy.dithering,
        PngStrategy.alphaSnap,
      },
    ),
  ),

  /// As small as reasonable: quality level 60 (error ≤ 24), exhaustive
  /// search, metadata stripped.
  smallest(
    'Smallest files: quality level 60 (error ≤ 24), exhaustive search, '
    'metadata stripped.',
    PngMinifyOptions(
      quality: PngQuality.maxError(24),
      effort: PngEffort.max,
      metadata: PngMetadata.strip,
    ),
  );

  /// One line on what the preset is for.
  final String description;

  /// The options it stands for.
  final PngMinifyOptions options;

  const PngPreset(this.description, this.options);

  /// The CLI name: `pixel-art`, `lossless-max`, …
  String get cliName =>
      name.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');

  /// Finds a preset by [PngPreset.cliName] or Dart name.
  static PngPreset parse(String name) {
    for (final p in values) {
      if (p.cliName == name || p.name == name) return p;
    }
    throw FormatException('unknown preset "$name"');
  }
}
