/// Minify PNG images in pure Dart.
///
/// Many optimisation strategies compete — colour-type and bit-depth
/// reduction, palettes, palette orders, filters, deflate levels, and (when
/// the quality allows) bounded-error quantisers — and the smallest result
/// that meets the [PngQuality] wins. Output is deterministic across the VM,
/// dart2js and dart2wasm.
///
/// ```dart
/// import 'package:png_minifier/png_minifier.dart';
///
/// final result = const PngMinifier().minify(pngBytes); // lossless
/// final smaller = PngMinifier.preset(PngPreset.web).minify(pngBytes);
/// ```
library;

export 'src/api/png_minifier.dart';
export 'src/api/png_options.dart';
export 'src/api/png_preset.dart';
export 'src/api/png_quality.dart';
export 'src/api/png_result.dart';
export 'src/image/png_image.dart';
export 'src/png/png_chunk.dart' show PngChunk;
export 'src/png/png_decoder.dart';
export 'src/png/png_encoder.dart' show encodePng;
export 'src/png/png_exception.dart';
export 'src/png/png_filters.dart' show PngFilterStrategy;
export 'src/png/png_raster.dart';
export 'src/version.dart';
