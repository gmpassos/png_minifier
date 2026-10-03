@Tags(['golden'])
library;

import 'package:crypto/crypto.dart';
import 'package:png_minifier/png_minifier.dart';
import 'package:test/test.dart';

import '../support/test_images.dart';

/// The minified bytes must be identical on the VM, dart2js and dart2wasm:
/// these SHA-256 prefixes were recorded on the VM, and CI checks them on
/// Chrome with both web compilers.
///
/// After an intentional output change, run `dart test -t golden` and copy
/// the printed map here.
const _expected = <String, String>{
  'sprite/fast':
      'c034e66b502fa554 5f29290e 358 exact/palette8(frequency)/none/z9',
  'sprite/lossless':
      'c034e66b502fa554 7d0b5b9c 358 exact/palette8(frequency)/none/z9',
  'sprite/max':
      'c034e66b502fa554 271037e1 358 exact/palette8(frequency)/none/z9',
  'sprite/e12':
      'c034e66b502fa554 adc968fc 358 exact/palette8(frequency)/none/z9',
  'sprite/psnr36max':
      'c034e66b502fa554 8b0d9c6e 358 exact/palette8(frequency)/none/z9',
  'gradient/fast': 'dd3d80059b8946af fe7af268 296 exact/rgba8/minSum/z9',
  'gradient/lossless': 'dd3d80059b8946af 84cb65c4 296 exact/rgba8/minSum/z9',
  'gradient/max': 'f69f9ea9f4b3793a d8416dd6 296 exact/rgba8/paeth/z9',
  'gradient/e12': 'dd3d80059b8946af fd452a34 296 exact/rgba8/minSum/z9',
  'gradient/psnr36max': 'f69f9ea9f4b3793a aa30f8aa 296 exact/rgba8/paeth/z9',
  'noisy/fast': 'd52eb999a541dae7 5c12dd9e 4764 exact/rgb8/minSum/z6',
  'noisy/lossless': 'd52eb999a541dae7 fe86fbc2 4764 exact/rgb8/minSum/z6',
  'noisy/max': 'd051afd7af489f1e bc9cd51b 4719 exact/rgb8/paeth/z6',
  'noisy/e12': 'd52eb999a541dae7 fe86fbc2 4764 exact/rgb8/minSum/z6',
  'noisy/psnr36max': 'd051afd7af489f1e bc9cd51b 4719 exact/rgb8/paeth/z6',
  'grey/fast': '0642cf7d72650ead 32ceeb37 255 exact/grey4/none/z6',
  'grey/lossless': 'ff98e80afbefa8e1 24e0980e 230 exact/grey4/minSum/z6',
  'grey/max': '91424a2d379f37d9 fbb69633 218 exact/grey4/sub/z6',
  'grey/e12': 'ff98e80afbefa8e1 47da4d01 230 exact/grey4/minSum/z6',
  'grey/psnr36max': '91424a2d379f37d9 2dc0fa6f 218 exact/grey4/sub/z6',
  'deep/fast': '3bec4133e0eba887 6a2deaa1 939 original',
  'deep/lossless': 'b7d354864e241221 39fda3f1 414 exact/rgba8/minSum/z9',
  'deep/max': 'f9c8a02da8ef4744 3c69be98 395 exact/rgba8/paeth/z6',
  'deep/e12': 'b7d354864e241221 76f6d920 414 exact/rgba8/minSum/z9',
  'deep/psnr36max':
      '3a381d6a38ae2230 0aaa5ebf 390 frequency(e64)/rgba8/paeth/z9',
};

final _images = <String, PngImage Function()>{
  'sprite': () => spriteImage(48, 40, colors: 9, rareShades: true),
  'gradient': () => gradientImage(48, 40),
  'noisy': () => noisyImage(48, 40),
  'grey': () => greyImage(33, 21, step: 17),
  'deep': () => deepImage(20, 16),
};

final _options = <String, PngMinifyOptions>{
  'fast': const PngMinifyOptions(effort: PngEffort.fast),
  'lossless': const PngMinifyOptions(),
  'max': const PngMinifyOptions(effort: PngEffort.max),
  'e12': const PngMinifyOptions(quality: PngQuality.maxError(12)),
  'psnr36max': const PngMinifyOptions(
    quality: PngQuality.psnr(36),
    effort: PngEffort.max,
  ),
};

void main() {
  test('output bytes are identical on every platform', () {
    final actual = <String, String>{};
    for (final MapEntry(key: imageName, value: build) in _images.entries) {
      final input = plainPng(build());
      for (final MapEntry(key: optionName, value: options)
          in _options.entries) {
        final r = PngMinifier(options).minify(input);
        // Every candidate's name and size too, so a platform difference in
        // any strategy shows, not only in the winning one.
        final tried = sha256
            .convert(r.candidates.join(';').codeUnits)
            .toString()
            .substring(0, 8);
        actual['$imageName/$optionName'] =
            '${sha256.convert(r.bytes).toString().substring(0, 16)} '
            '$tried ${r.size} ${r.strategy}';
      }
    }
    final mismatches = [
      for (final k in actual.keys)
        if (_expected[k] != actual[k]) k,
    ];
    if (mismatches.isNotEmpty) {
      final printed = actual.entries
          .map((e) => "  '${e.key}': '${e.value}',")
          .join('\n');
      fail(
        '${mismatches.length} outputs differ: $mismatches\n'
        'actual:\n{\n$printed\n}',
      );
    }
  });
}
