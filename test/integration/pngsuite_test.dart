@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:png_minifier/png_minifier.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// package:image 4.x throws a RangeError on the tiny interlaced 1-bit
/// palette files; each has a non-interlaced twin with the same pixels.
const _interlacedTwins = {
  's01i3p01.png': 's01n3p01.png',
  's02i3p01.png': 's02n3p01.png',
  's03i3p01.png': 's03n3p01.png',
  's04i3p01.png': 's04n3p01.png',
};

/// package:image 4.x ignores the tRNS key of 16-bit greyscale. In
/// tbwn0g16 the key is 0xFFFF: white pixels are transparent.
const _greyKey16 = {'tbwn0g16.png': 0xffff};

/// The independent decode of PngSuite file [f], working around the
/// package:image bugs above.
Uint16List oracle(File f) {
  final name = nameOf(f);
  final twin = _interlacedTwins[name];
  if (twin != null) {
    return oracleRgba16(File('test/fixtures/pngsuite/$twin').readAsBytesSync());
  }
  final pixels = oracleRgba16(f.readAsBytesSync());
  final key = _greyKey16[name];
  if (key != null) {
    for (var i = 0; i < pixels.length; i += 4) {
      if (pixels[i] == key) pixels[i + 3] = 0;
    }
  }
  return pixels;
}

/// PngSuite: every standard PNG variant, plus corrupt files (`x*`).
void main() {
  final files = fixtures('pngsuite');
  final valid = files.where((f) => !nameOf(f).startsWith('x')).toList();
  final corrupt = files.where((f) => nameOf(f).startsWith('x')).toList();

  test('the suite is present', () {
    expect(valid.length, greaterThan(150));
    expect(corrupt.length, 14);
  });

  group('decoder agrees with package:image', () {
    for (final f in valid) {
      test(nameOf(f), () {
        final bytes = f.readAsBytesSync();
        final ours = const PngDecoder().decode(bytes).image;
        expect(sameVisible16(rgba16Of(ours), oracle(f)), isTrue);
      });
    }
  });

  group('corrupt files are rejected', () {
    for (final f in corrupt) {
      test(nameOf(f), () {
        expect(
          () => const PngDecoder().decode(f.readAsBytesSync()),
          throwsA(isA<PngFormatException>()),
        );
      });
    }
  });

  group('lossless minify keeps every pixel', () {
    for (final f in valid) {
      test(nameOf(f), () {
        final bytes = f.readAsBytesSync();
        final source = const PngDecoder().decode(bytes).image;
        final r = const PngMinifier().minify(bytes);
        expect(r.size, lessThanOrEqualTo(bytes.length));
        expect(r.lossless, isTrue);
        // Checked by an independent decoder, not only our own.
        final decoded = r.unchanged ? oracle(f) : oracleRgba16(r.bytes);
        expect(sameVisible16(rgba16Of(source), decoded), isTrue);
      });
    }
  });

  test('the suite shrinks overall', () {
    var before = 0;
    var after = 0;
    for (final f in valid) {
      final bytes = f.readAsBytesSync();
      before += bytes.length;
      after += const PngMinifier().minify(bytes).size;
    }
    expect(after, lessThan(before * 0.9));
  });
}
