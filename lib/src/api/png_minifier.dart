import 'dart:typed_data';

import '../image/color_histogram.dart';
import '../image/image_diff.dart';
import '../image/png_image.dart';
import '../optimize/palette_order.dart';
import '../optimize/representations.dart';
import '../png/png_chunk.dart';
import '../png/png_decoder.dart';
import '../png/png_encoder.dart';
import '../png/png_filters.dart';
import '../png/png_raster.dart';
import '../quantize/dither.dart';
import '../quantize/frequency_quantizer.dart';
import '../quantize/median_cut_quantizer.dart';
import '../quantize/palette_mapper.dart';
import '../quantize/posterize.dart';
import 'png_options.dart';
import 'png_preset.dart';
import 'png_result.dart';

/// Minifies PNG images.
///
/// Every active [PngStrategy] proposes candidate encodings; candidates that
/// break the [PngMinifyOptions.quality] are rejected, and the smallest of
/// the rest wins (ties go to the first tried, so the output is
/// deterministic). The input itself is returned when nothing is smaller.
///
/// ```dart
/// final result = PngMinifier.preset(PngPreset.pixelArt).minify(bytes);
/// print('${result.originalSize} -> ${result.size} (${result.strategy})');
/// ```
class PngMinifier {
  /// The options in effect.
  final PngMinifyOptions options;

  /// A minifier with [options] (lossless and balanced by default).
  const PngMinifier([this.options = const PngMinifyOptions()]);

  /// A minifier with the options of [preset].
  PngMinifier.preset(PngPreset preset) : options = preset.options;

  /// Minifies the PNG file [bytes]. Throws `PngFormatException` when they
  /// are not a valid PNG.
  PngMinifyResult minify(Uint8List bytes) {
    final decoded = const PngDecoder().decode(bytes);
    if (decoded.animated) {
      return _unchanged(
        bytes,
        decoded,
        'animated PNG (APNG): only the default image could be optimised',
      );
    }
    return _run(
      decoded.image,
      original: bytes,
      originalDecoded: decoded,
      ancillary: _keptChunks(decoded.ancillary),
    );
  }

  /// Encodes [image] as small as the options allow — for callers that hold
  /// pixels rather than a PNG file. [PngMinifyResult.originalSize] is then
  /// the raw RGBA size.
  PngMinifyResult minifyImage(PngImage image) =>
      _run(image, original: null, originalDecoded: null, ancillary: const []);

  static const _colorChunks = {
    'gAMA',
    'cHRM',
    'sRGB',
    'iCCP',
    'cICP',
    'mDCV',
    'mDCv',
    'cLLI',
    'cLLi',
  };

  // Chunks whose meaning depends on the colour type or the image data.
  static const _invalidated = {'bKGD', 'hIST', 'sBIT', 'acTL', 'fcTL', 'fdAT'};

  static const _knownSafe = {
    'pHYs',
    'tEXt',
    'zTXt',
    'iTXt',
    'tIME',
    'eXIf',
    'sPLT',
    'oFFs',
    'pCAL',
    'sCAL',
  };

  List<PngChunk> _keptChunks(List<PngChunk> chunks) =>
      switch (options.metadata) {
        PngMetadata.strip => const [],
        PngMetadata.color => [
          for (final c in chunks)
            if (_colorChunks.contains(c.type)) c,
        ],
        PngMetadata.all => [
          for (final c in chunks)
            if (!_invalidated.contains(c.type) &&
                (_colorChunks.contains(c.type) ||
                    _knownSafe.contains(c.type) ||
                    c.isSafeToCopy))
              c,
        ],
      };

  PngMinifyResult _unchanged(
    Uint8List bytes,
    PngDecoded decoded,
    String reason, [
    List<PngCandidateReport> candidates = const [],
  ]) => PngMinifyResult(
    bytes: bytes,
    originalSize: bytes.length,
    unchanged: true,
    reason: reason,
    strategy: 'original',
    lossless: true,
    changedPixels: 0,
    maxChannelError: 0,
    psnr: double.infinity,
    width: decoded.image.width,
    height: decoded.image.height,
    colorType: decoded.colorType,
    bitDepth: decoded.bitDepth,
    candidates: candidates,
  );

  PngMinifyResult _run(
    PngImage image, {
    required Uint8List? original,
    required PngDecoded? originalDecoded,
    required List<PngChunk> ancillary,
  }) {
    final transforms = _transforms(image);
    final reports = <PngCandidateReport>[];
    _Best? best;
    void consider(_Best candidate) {
      reports.add(PngCandidateReport(candidate.name, candidate.bytes.length));
      if (best == null || candidate.bytes.length < best!.bytes.length) {
        best = candidate;
      }
    }

    // Stage 1: every transform × representation × filter, compressed at the
    // quicker deflate level 6. Each is a valid candidate; the most promising
    // few are kept for stage 2.
    final keep = switch (options.effort) {
      PngEffort.fast => 1,
      PngEffort.balanced => 2,
      PngEffort.max => 4,
    };
    final shortlist = <_Best>[];
    for (final t in transforms) {
      final histogram = ColorHistogram.of(t.image);
      var rasters = buildRepresentations(
        t.image,
        histogram,
        reduceColorType: options.uses(PngStrategy.colorTypeReduction),
        palette: options.uses(PngStrategy.palette),
        orders: options.uses(PngStrategy.paletteOrdering)
            ? PaletteOrder.values.toSet()
            : const {PaletteOrder.frequency},
        preserveTransparentColor: options.preserveTransparentColor,
      );
      if (options.effort == PngEffort.fast) rasters = rasters.take(1).toList();
      for (final raster in rasters) {
        for (final filter in _filtersFor(raster)) {
          final c = _encode(t, raster, filter, _proxyLevel, ancillary);
          consider(c);
          // Insert by size, ties after earlier ones; drop past `keep`.
          var at = shortlist.length;
          while (at > 0 && shortlist[at - 1].bytes.length > c.bytes.length) {
            at--;
          }
          if (at < keep) {
            shortlist.insert(at, c);
            if (shortlist.length > keep) shortlist.removeLast();
          }
        }
      }
    }

    // Stage 2: the shortlist at full compression, and (deflate search)
    // more levels for the leader.
    for (final c in shortlist) {
      consider(_encode(c.transform, c.raster, c.filter, 9, ancillary));
    }
    if (options.uses(PngStrategy.deflateSearch) &&
        options.effort == PngEffort.max) {
      final lead = shortlist.first;
      for (final level in const [8, 7]) {
        consider(
          _encode(lead.transform, lead.raster, lead.filter, level, ancillary),
        );
      }
    }
    final winner = best!;

    if (original != null && winner.bytes.length >= original.length) {
      return _unchanged(
        original,
        originalDecoded!,
        'no candidate was smaller than the input',
        reports,
      );
    }

    if (options.verify) _verify(winner);

    final diff = ImageDiff.of(image, winner.transform.image);
    return PngMinifyResult(
      bytes: winner.bytes,
      originalSize: original?.length ?? image.pixelCount * 4,
      strategy: winner.name,
      lossless: winner.transform.lossless,
      changedPixels: diff.changedPixels,
      maxChannelError: diff.maxError,
      psnr: diff.psnr,
      width: image.width,
      height: image.height,
      colorType: winner.raster.colorType,
      bitDepth: winner.raster.bitDepth,
      paletteSize: winner.raster.palette == null
          ? null
          : winner.raster.palette!.length ~/ 3,
      candidates: reports,
    );
  }

  void _verify(_Best winner) {
    final decoded = const PngDecoder().decode(winner.bytes).image;
    final expected = winner.transform.image;
    if (!decoded.sameAs(
      expected,
      compareTransparentColor: options.preserveTransparentColor,
    )) {
      throw StateError(
        'png_minifier produced an image that does not decode to the '
        'expected pixels (${winner.name}); please report this',
      );
    }
  }

  List<PngFilterStrategy> _filtersFor(PngRaster raster) {
    if (options.uses(PngStrategy.filterSearch)) {
      if (options.effort == PngEffort.max) return PngFilterStrategy.values;
      return const [
        PngFilterStrategy.none,
        PngFilterStrategy.minSum,
        PngFilterStrategy.entropy,
      ];
    }
    // Without a search: no filter for palettes and sub-byte samples (their
    // bytes are not smooth), else the plain and the minimum-sum choice —
    // flat areas, like transparent sprite margins, often favour none.
    final lowDepth =
        raster.bitDepth < 8 || raster.colorType == PngColorType.indexed;
    return lowDepth
        ? const [PngFilterStrategy.none]
        : const [PngFilterStrategy.none, PngFilterStrategy.minSum];
  }

  static const _proxyLevel = 6;

  _Best _encode(
    _Transform t,
    PngRaster raster,
    PngFilterStrategy filter,
    int level,
    List<PngChunk> ancillary,
  ) {
    final idat = compressRaster(raster, filter: filter, level: level);
    final bytes = assemblePng(raster, idat, ancillary: ancillary);
    final name = '${t.name}/${raster.label}/${filter.name}/z$level';
    return _Best(name, bytes, t, raster, filter);
  }

  /// The images to encode: the exact one, then the lossy ones that keep the
  /// quality.
  List<_Transform> _transforms(PngImage image) {
    final exact =
        options.uses(PngStrategy.transparentCleanup) &&
            !options.preserveTransparentColor
        ? clearTransparent(image)
        : image;
    final out = [_Transform('exact', exact, lossless: true)];
    final quality = options.quality;
    if (quality.isLossless) return out;

    final base = exact.isDeep
        ? PngImage(exact.width, exact.height, exact.pixels)
        : exact;
    final histogram = ColorHistogram.of(base);
    final maxColors = options.maxColors;
    final fast = options.effort == PngEffort.fast;
    final max = options.effort == PngEffort.max;
    final lossy = <_Transform>[];

    bool accept(String name, PngImage? candidate) {
      if (candidate == null) return false;
      if (fast && lossy.isNotEmpty) return false;
      final diff = ImageDiff.of(image, candidate);
      if (diff.maxError > quality.maxError) return false;
      final minPsnr = quality.minPsnr;
      if (minPsnr != null && !diff.psnrAtLeast(minPsnr)) return false;
      lossy.add(_Transform(name, candidate, lossless: false));
      return true;
    }

    // Error bounds to try: the quality's own, or — when only PSNR is
    // limited — a ladder from coarse to fine, the coarsest passing first.
    final bounds = quality.minPsnr == null
        ? [quality.maxError]
        : [
            for (final e in const [64, 32, 16, 8, 4, 2])
              if (e <= quality.maxError) e,
          ];

    // Accepted palettes and their bounds, for dithering.
    final palettes = <String, (PaletteIndex, int)>{};

    if (options.uses(PngStrategy.frequencyPalette)) {
      for (final e in bounds) {
        final palette = frequencyPalette(
          histogram,
          maxColors: maxColors,
          maxError: e,
        );
        if (palette == null) continue;
        if (accept('frequency(e$e)', remap(base, histogram, palette, e))) {
          palettes['frequency(e$e)'] = (palette, e);
          if (!max) break;
        }
      }
    }

    final guard = quality.maxError;
    final needsReduction = histogram.length > maxColors;
    if (options.uses(PngStrategy.medianCutPalette) && needsReduction) {
      final palette = guardedPalette(
        histogram,
        (n) => medianCut(histogram, n),
        maxColors: maxColors,
        maxError: guard,
      );
      if (palette != null &&
          accept('median-cut', remap(base, histogram, palette, guard))) {
        palettes['median-cut'] = (palette, guard);
      }
    }

    if (options.uses(PngStrategy.kMeansPalette) && needsReduction) {
      final palette = guardedPalette(
        histogram,
        (n) => kMeansRefine(histogram, medianCut(histogram, n)),
        maxColors: maxColors,
        maxError: guard,
      );
      if (palette != null &&
          accept('k-means', remap(base, histogram, palette, guard))) {
        palettes['k-means'] = (palette, guard);
      }
    }

    if (options.uses(PngStrategy.dithering) && needsReduction) {
      for (final MapEntry(key: name, value: (palette, bound))
          in palettes.entries) {
        accept('dither+$name', ditherFloydSteinberg(base, palette, bound));
      }
    }

    if (options.uses(PngStrategy.posterize) && quality.maxError < 255) {
      accept(
        'posterize(e${quality.maxError})',
        posterize(base, quality.maxError),
      );
    }

    if (options.uses(PngStrategy.alphaSnap) && quality.maxError < 255) {
      accept(
        'alpha-snap(e${quality.maxError})',
        snapAlpha(base, quality.maxError),
      );
    }

    if (exact.isDeep) {
      accept('8-bit', base);
    }
    return [...out, ...lossy];
  }
}

class _Transform {
  final String name;
  final PngImage image;
  final bool lossless;
  _Transform(this.name, this.image, {required this.lossless});
}

class _Best {
  final String name;
  final Uint8List bytes;
  final _Transform transform;
  final PngRaster raster;
  final PngFilterStrategy filter;
  _Best(this.name, this.bytes, this.transform, this.raster, this.filter);
}
