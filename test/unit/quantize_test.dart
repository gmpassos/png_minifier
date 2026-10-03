import 'dart:typed_data';

import 'package:png_minifier/png_minifier.dart';
import 'package:png_minifier/src/image/color.dart';
import 'package:png_minifier/src/image/color_histogram.dart';
import 'package:png_minifier/src/image/image_diff.dart';
import 'package:png_minifier/src/quantize/dither.dart';
import 'package:png_minifier/src/quantize/frequency_quantizer.dart';
import 'package:png_minifier/src/quantize/median_cut_quantizer.dart';
import 'package:png_minifier/src/quantize/palette_mapper.dart';
import 'package:png_minifier/src/quantize/posterize.dart';
import 'package:test/test.dart';

import '../support/test_images.dart';

int distinct(PngImage image) => ColorHistogram.of(image).length;

void main() {
  group('PaletteIndex', () {
    final index = PaletteIndex([
      packRgba(0, 0, 0, 255),
      packRgba(100, 100, 100, 255),
      packRgba(0, 0, 0, 0),
    ]);

    test('covers and nearest honour the bound', () {
      expect(index.length, 3);
      expect(index.covers(packRgba(5, 5, 5, 255), 5), isTrue);
      expect(index.covers(packRgba(50, 50, 50, 255), 10), isFalse);
      expect(index.nearest(packRgba(60, 60, 60, 255), 255), 1);
      expect(index.nearest(packRgba(40, 40, 40, 255), 255), 0);
      expect(index.nearest(packRgba(50, 50, 50, 255), 10), -1);
      // Any transparent colour is at distance 0 from transparent black.
      expect(index.nearest(packRgba(9, 9, 9, 0), 0), 2);
    });

    test('remap fails when a colour is out of range', () {
      final image = PngImage(1, 1, Uint8List.fromList([60, 60, 60, 255]));
      final h = ColorHistogram.of(image);
      expect(remap(image, h, index, 10), isNull);
      expect(remap(image, h, index, 60)!.pixels, [100, 100, 100, 255]);
      expect(uncovered(h, index, 10), [packRgba(60, 60, 60, 255)]);
    });
  });

  group('frequencyPalette', () {
    test('keeps every colour when they fit', () {
      final image = spriteImage(30, 30, colors: 10);
      final h = ColorHistogram.of(image);
      final p = frequencyPalette(h, maxColors: 256, maxError: 0)!;
      expect(p.length, h.length);
    });

    test('merges rare shades within the bound', () {
      final image = clearTransparent(
        spriteImage(60, 60, colors: 40, rareShades: true),
      );
      final h = ColorHistogram.of(image);
      final p = frequencyPalette(h, maxColors: 41, maxError: 4)!;
      expect(p.length, lessThanOrEqualTo(41));
      final out = remap(image, h, p, 4)!;
      final diff = ImageDiff.of(image, out);
      expect(diff.maxError, lessThanOrEqualTo(4));
      expect(diff.changedPixels, lessThan(image.pixelCount ~/ 20));
    });

    test('returns null when the bound cannot hold', () {
      final h = ColorHistogram.of(noisyImage(32, 32));
      expect(frequencyPalette(h, maxColors: 4, maxError: 2), isNull);
    });

    test('is deterministic', () {
      final h = ColorHistogram.of(noisyImage(32, 32));
      final a = frequencyPalette(h, maxColors: 256, maxError: 20)!.entries;
      final b = frequencyPalette(h, maxColors: 256, maxError: 20)!.entries;
      expect(a, b);
    });
  });

  group('median cut and k-means', () {
    final image = noisyImage(48, 48);
    final h = ColorHistogram.of(image);

    test('median cut returns the requested number of colours', () {
      expect(medianCut(h, 16).length, 16);
      final few = ColorHistogram.of(spriteImage(10, 10, colors: 3));
      expect(medianCut(few, 16).length, few.length);
    });

    test('transparent boxes stay transparent black', () {
      final h2 = ColorHistogram.of(
        PngImage(2, 1, Uint8List.fromList([0, 0, 0, 0, 255, 255, 255, 255])),
      );
      expect(medianCut(h2, 1), hasLength(1));
      final clear = ColorHistogram.of(
        PngImage(2, 1, Uint8List.fromList([5, 6, 7, 0, 8, 9, 10, 0])),
      );
      expect(medianCut(clear, 1), [0]);
    });

    test('k-means does not increase the mapping error', () {
      double mse(List<int> palette) {
        final index = PaletteIndex(palette);
        var sse = 0;
        for (var i = 0; i < h.length; i++) {
          final e = index.entries[index.nearest(h.colors[i], 255)];
          sse += colorSquaredError(h.colors[i], e) * h.counts[i];
        }
        return sse / image.pixelCount;
      }

      final mc = medianCut(h, 16);
      final km = kMeansRefine(h, mc);
      expect(km.length, lessThanOrEqualTo(16));
      expect(mse(km), lessThanOrEqualTo(mse(mc)));
    });

    test('guardedPalette holds the bound or gives up', () {
      final p = guardedPalette(
        h,
        (n) => medianCut(h, n),
        maxColors: 256,
        maxError: 24,
      )!;
      expect(p.length, lessThanOrEqualTo(256));
      final out = remap(image, h, p, 24)!;
      expect(ImageDiff.of(image, out).maxError, lessThanOrEqualTo(24));
      expect(
        guardedPalette(h, (n) => medianCut(h, n), maxColors: 8, maxError: 1),
        isNull,
      );
    });
  });

  group('ditherFloydSteinberg', () {
    test('keeps every pixel within the bound', () {
      final image = gradientImage(40, 30);
      final h = ColorHistogram.of(image);
      final palette = guardedPalette(
        h,
        (n) => medianCut(h, n),
        maxColors: 256,
        maxError: 16,
      )!;
      final out = ditherFloydSteinberg(image, palette, 16)!;
      expect(ImageDiff.of(image, out).maxError, lessThanOrEqualTo(16));
      final again = ditherFloydSteinberg(image, palette, 16)!;
      expect(again.pixels, out.pixels);
    });

    test('handles transparency and out-of-range palettes', () {
      final image = clearTransparent(spriteImage(12, 12, colors: 4));
      final h = ColorHistogram.of(image);
      final palette = PaletteIndex(h.colors);
      expect(ditherFloydSteinberg(image, palette, 0)!.pixels, image.pixels);
      expect(
        ditherFloydSteinberg(image, PaletteIndex([packRgba(0, 0, 0, 0)]), 3),
        isNull,
      );
    });
  });

  group('posterize, snapAlpha, clearTransparent', () {
    test('posterize stays within the bound and reduces colours', () {
      final image = noisyImage(30, 30);
      final out = posterize(image, 8)!;
      expect(ImageDiff.of(image, out).maxError, lessThanOrEqualTo(8));
      expect(distinct(out), lessThan(distinct(image)));
      expect(posterize(image, 0), isNull);
      final flat = PngImage(1, 1, Uint8List.fromList([0, 255, 0, 255]));
      expect(posterize(flat, 4), isNull);
    });

    test('snapAlpha pushes alpha to 0 or 255', () {
      final image = PngImage(
        3,
        1,
        Uint8List.fromList([
          ...[10, 20, 30, 3],
          ...[10, 20, 30, 252],
          ...[10, 20, 30, 128],
        ]),
      );
      final out = snapAlpha(image, 4)!;
      expect(out.pixels, [0, 0, 0, 0, 10, 20, 30, 255, 10, 20, 30, 128]);
      expect(ImageDiff.of(image, out).maxError, lessThanOrEqualTo(4));
      expect(snapAlpha(image, 0), isNull);
      expect(snapAlpha(spriteImage(5, 5), 4), isNull);
    });

    test('clearTransparent blackens invisible pixels only', () {
      final image = spriteImage(8, 8, colouredTransparency: true);
      final out = clearTransparent(image);
      expect(out.sameAs(image), isTrue);
      expect(out.sameAs(image, compareTransparentColor: true), isFalse);
      expect(identical(clearTransparent(out), out), isTrue);

      final s = Uint16List.fromList([7, 7, 7, 0, 1, 2, 3, 0xffff]);
      final deep = PngImage(
        2,
        1,
        Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 255]),
        pixels16: s,
      );
      expect(clearTransparent(deep).pixels16!.take(3), [0, 0, 0]);
    });
  });
}
