import 'dart:io';

import 'package:png_minifier/png_minifier.dart';

/// Minifies a PNG three ways and prints what each one gave.
///
///     dart run example/png_minifier_example.dart image.png
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run example/png_minifier_example.dart '
      '<image.png>',
    );
    exitCode = 64;
    return;
  }
  final bytes = File(args.first).readAsBytesSync();

  // Same pixels, fewer bytes (the default).
  final lossless = const PngMinifier().minify(bytes);
  print('lossless:  $lossless');

  // A preset: popular colours exact, rare ones within 12 levels.
  final pixelArt = PngMinifier.preset(PngPreset.pixelArt).minify(bytes);
  print('pixel art: $pixelArt');

  // Custom quality: PSNR of at least 45 dB, exhaustive search.
  final custom = const PngMinifier(
    PngMinifyOptions(quality: PngQuality.psnr(45), effort: PngEffort.max),
  ).minify(bytes);
  print('psnr 45:   $custom (psnr ${custom.psnr.toStringAsFixed(1)} dB)');

  File('${args.first}.min.png').writeAsBytesSync(lossless.bytes);
}
