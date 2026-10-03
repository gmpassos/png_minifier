import 'dart:typed_data';

import 'package:png_minifier/png_minifier.dart';
import 'package:png_minifier/src/image/color.dart';
import 'package:png_minifier/src/image/color_histogram.dart';
import 'package:png_minifier/src/image/image_diff.dart';
import 'package:test/test.dart';

import '../support/test_images.dart';

void main() {
  group('color', () {
    test('packs and unpacks without sign problems', () {
      final c = packRgba(255, 128, 1, 254);
      expect(c, 0xff8001fe);
      expect(c, isPositive);
      expect([redOf(c), greenOf(c), blueOf(c), alphaOf(c)], [255, 128, 1, 254]);
      final px = Uint8List.fromList([1, 2, 3, 4, 250, 251, 252, 253]);
      expect(colorAt(px, 1), packRgba(250, 251, 252, 253));
    });

    test('colorError ignores the colour of transparent pixels', () {
      expect(colorError(packRgba(255, 0, 0, 0), packRgba(0, 255, 9, 0)), 0);
      expect(
        colorError(packRgba(10, 20, 30, 255), packRgba(13, 20, 28, 255)),
        3,
      );
      // A faint pixel's colour counts only as much as it shows.
      expect(colorError(packRgba(255, 0, 0, 10), packRgba(0, 0, 0, 10)), 10);
      expect(colorError(packRgba(0, 0, 0, 0), packRgba(0, 0, 0, 7)), 7);
    });

    test('distance, squared error and luma', () {
      final a = packRgba(10, 10, 10, 255);
      expect(colorDistance(a, a), 0);
      expect(colorDistance(a, packRgba(10, 11, 10, 255)), 4);
      expect(colorDistance(a, packRgba(11, 10, 10, 255)), 2);
      expect(colorSquaredError(a, packRgba(12, 10, 10, 255)), 4);
      expect(lumaOf(packRgba(255, 255, 255, 255)), 255);
      expect(lumaOf(packRgba(0, 255, 0, 255)), 149);
      expect(premultiply(255, 128), 128);
    });
  });

  group('PngImage', () {
    test('validates sizes', () {
      expect(() => PngImage(0, 1, Uint8List(0)), throwsArgumentError);
      expect(() => PngImage(1, 1, Uint8List(3)), throwsArgumentError);
      expect(
        () => PngImage(1, 1, Uint8List(4), pixels16: Uint16List(3)),
        throwsArgumentError,
      );
    });

    test('fromArgb converts 0xAARRGGBB words', () {
      final image = PngImage.fromArgb(2, 1, [0xff102030, 0x80ff0000]);
      expect(image.pixels, [0x10, 0x20, 0x30, 0xff, 0xff, 0, 0, 0x80]);
      expect(() => PngImage.fromArgb(2, 2, [0]), throwsArgumentError);
    });

    test('sameAs compares visible pixels', () {
      final a = PngImage(1, 2, Uint8List.fromList([1, 2, 3, 0, 4, 5, 6, 255]));
      final b = PngImage(1, 2, Uint8List.fromList([9, 9, 9, 0, 4, 5, 6, 255]));
      expect(a.sameAs(b), isTrue);
      expect(a.sameAs(b, compareTransparentColor: true), isFalse);
      final c = PngImage(1, 2, Uint8List.fromList([1, 2, 3, 0, 4, 5, 7, 255]));
      expect(a.sameAs(c), isFalse);
      expect(a.sameAs(PngImage(2, 1, Uint8List(8))), isFalse);
      final d = PngImage(1, 2, Uint8List.fromList([1, 2, 3, 1, 4, 5, 6, 255]));
      expect(a.sameAs(d), isFalse);
      expect(a.toString(), 'PngImage(1x2)');
    });

    test('sameAs compares 16-bit samples', () {
      final deep = deepImage(3, 3);
      expect(deep.sameAs(deep), isTrue);
      expect(deep.sameAs(PngImage(3, 3, deep.pixels)), isFalse);
      final other = PngImage(
        3,
        3,
        deep.pixels,
        pixels16: Uint16List.fromList(deep.pixels16!)..[0] ^= 1,
      );
      expect(deep.sameAs(other), isFalse);
      final alpha = Uint16List.fromList(deep.pixels16!)..[3] ^= 1;
      expect(
        deep.sameAs(PngImage(3, 3, deep.pixels, pixels16: alpha)),
        isFalse,
      );
      expect(deep.toString(), contains('16-bit'));
    });
  });

  group('ColorHistogram', () {
    test('counts colours, most used first, ties by value', () {
      final image = PngImage(
        4,
        1,
        Uint8List.fromList([
          ...[5, 5, 5, 255],
          ...[1, 1, 1, 255],
          ...[5, 5, 5, 255],
          ...[0, 0, 0, 0],
        ]),
      );
      final h = ColorHistogram.of(image);
      expect(h.length, 3);
      expect(h.colors.first, packRgba(5, 5, 5, 255));
      expect(h.counts, [2, 1, 1]);
      expect(h.colors[1], packRgba(0, 0, 0, 0)); // 0 < 0x01010101ff
      expect(h.grey, isTrue);
      expect(h.opaque, isFalse);
      expect(h.binaryAlpha, isTrue);
    });

    test('detects colour and partial alpha', () {
      final h = ColorHistogram.of(gradientImage(8, 8));
      expect(h.grey, isFalse);
      expect(h.binaryAlpha, isFalse);
      expect(ColorHistogram.of(noisyImage(8, 8)).opaque, isTrue);
    });
  });

  group('ImageDiff', () {
    test('identical images', () {
      final image = gradientImage(6, 6);
      final diff = ImageDiff.of(image, image);
      expect(diff.changedPixels, 0);
      expect(diff.maxError, 0);
      expect(diff.psnr, double.infinity);
      expect(diff.psnrAtLeast(100), isTrue);
    });

    test('measures changes', () {
      final a = noisyImage(10, 10);
      final changed = Uint8List.fromList(a.pixels)
        ..[0] = (a.pixels[0] + 8) % 256;
      final diff = ImageDiff.of(a, PngImage(10, 10, changed));
      expect(diff.changedPixels, 1);
      expect(diff.maxError, 8);
      expect(diff.squaredError, 64);
      // MSE = 64 / (100 pixels × 4 channels); 10·log10(255² / 0.16).
      expect(diff.psnr, closeTo(56.09, 0.01));
      expect(diff.psnrAtLeast(diff.psnr - 0.01), isTrue);
      expect(diff.psnrAtLeast(diff.psnr + 0.01), isFalse);
      expect(() => ImageDiff.of(a, noisyImage(5, 5)), throwsArgumentError);
    });
  });
}
