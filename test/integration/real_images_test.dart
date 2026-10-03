@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:png_minifier/png_minifier.dart';
import 'package:png_minifier/src/image/image_diff.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

PngImage decode(Uint8List bytes) => const PngDecoder().decode(bytes).image;

/// Real images: Kodak photo crops and Kenney game art.
void main() {
  group('Kodak photo crops', () {
    final files = fixtures('kodak');

    test('are present', () => expect(files, hasLength(3)));

    for (final f in files) {
      final bytes = f.readAsBytesSync();
      final source = decode(bytes);

      test('${nameOf(f)}: lossless shrinks, same pixels', () {
        final r = const PngMinifier().minify(bytes);
        expect(r.size, lessThan(bytes.length));
        expect(sameVisible16(rgba16Of(source), oracleRgba16(r.bytes)), isTrue);
      });

      test('${nameOf(f)}: photo preset keeps PSNR ≥ 38 dB, ≥ 40% smaller', () {
        final r = PngMinifier.preset(PngPreset.photo).minify(bytes);
        final diff = ImageDiff.of(source, decode(r.bytes));
        expect(diff.psnrAtLeast(38), isTrue);
        expect(r.size, lessThan(bytes.length * 0.6));
      });

      test('${nameOf(f)}: web preset holds error ≤ 12', () {
        final r = PngMinifier.preset(PngPreset.web).minify(bytes);
        expect(
          ImageDiff.of(source, decode(r.bytes)).maxError,
          lessThanOrEqualTo(12),
        );
        expect(r.size, lessThanOrEqualTo(bytes.length));
      });
    }
  });

  group('Kenney game art', () {
    final files = fixtures('kenney');

    test('are present', () => expect(files, hasLength(4)));

    for (final f in files) {
      final bytes = f.readAsBytesSync();
      final source = decode(bytes);

      test('${nameOf(f)}: lossless never grows, same pixels', () {
        final r = const PngMinifier().minify(bytes);
        expect(r.size, lessThanOrEqualTo(bytes.length));
        expect(sameVisible16(rgba16Of(source), oracleRgba16(r.bytes)), isTrue);
      });

      test('${nameOf(f)}: pixel-art preset holds error ≤ 12', () {
        final r = PngMinifier.preset(PngPreset.pixelArt).minify(bytes);
        expect(
          ImageDiff.of(source, decode(r.bytes)).maxError,
          lessThanOrEqualTo(12),
        );
        expect(r.size, lessThanOrEqualTo(bytes.length));
      });
    }

    test('the UI sample sheet shrinks losslessly', () {
      final f = files.firstWhere((f) => nameOf(f).startsWith('ui-pack'));
      final bytes = f.readAsBytesSync();
      expect(const PngMinifier().minify(bytes).size, lessThan(bytes.length));
    });
  });
}
