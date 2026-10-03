import 'dart:convert';
import 'dart:typed_data';

import 'package:png_minifier/png_minifier.dart';
import 'package:png_minifier/src/image/image_diff.dart';
import 'package:png_minifier/src/png/png_chunk.dart';
import 'package:test/test.dart';

import '../support/test_images.dart';

PngImage decode(Uint8List bytes) => const PngDecoder().decode(bytes).image;

void main() {
  group('PngMinifier lossless', () {
    test('shrinks a plain RGBA sprite to a palette, same pixels', () {
      final image = spriteImage(64, 48, colors: 6);
      final input = plainPng(image);
      final r = const PngMinifier().minify(input);
      expect(r.size, lessThan(input.length));
      expect(r.unchanged, isFalse);
      expect(r.lossless, isTrue);
      expect(r.changedPixels, 0);
      expect(r.maxChannelError, 0);
      expect(r.psnr, double.infinity);
      expect(r.colorType, PngColorType.indexed);
      expect(r.paletteSize, 7);
      expect(r.width, 64);
      expect(r.height, 48);
      expect(r.strategy, startsWith('exact/palette'));
      expect(r.candidates, isNotEmpty);
      expect(decode(r.bytes).sameAs(image), isTrue);
      expect(r.ratio, lessThan(1));
      expect(r.savedBytes, input.length - r.size);
    });

    test('returns the input when nothing is smaller', () {
      final tiny = const PngMinifier().minify(
        const PngMinifier().minify(plainPng(spriteImage(9, 9))).bytes,
      );
      final again = const PngMinifier().minify(tiny.bytes);
      expect(again.unchanged, isTrue);
      expect(again.reason, contains('smaller'));
      expect(
        identical(again.bytes, tiny.bytes) || again.bytes == tiny.bytes,
        isTrue,
      );
      expect(again.strategy, 'original');
    });

    test('every effort gives the same pixels; more effort is no larger', () {
      final image = gradientImage(48, 40);
      final input = plainPng(image);
      final sizes = <PngEffort, int>{};
      for (final effort in PngEffort.values) {
        final r = PngMinifier(PngMinifyOptions(effort: effort)).minify(input);
        expect(decode(r.bytes).sameAs(image), isTrue, reason: effort.name);
        sizes[effort] = r.size;
      }
      expect(sizes[PngEffort.max]!, lessThanOrEqualTo(sizes[PngEffort.fast]!));
      expect(
        sizes[PngEffort.max]!,
        lessThanOrEqualTo(sizes[PngEffort.balanced]!),
      );
    });

    test('preserveTransparentColor keeps invisible colours', () {
      final image = spriteImage(20, 20, colouredTransparency: true);
      final input = plainPng(image);
      final kept = const PngMinifier(
        PngMinifyOptions(preserveTransparentColor: true),
      ).minify(input);
      expect(
        decode(kept.bytes).sameAs(image, compareTransparentColor: true),
        isTrue,
      );
      final cleaned = const PngMinifier().minify(input);
      expect(cleaned.size, lessThan(kept.size));
      expect(decode(cleaned.bytes).sameAs(image), isTrue);
    });

    test('16-bit images stay 16-bit when lossless', () {
      final image = deepImage(16, 12);
      final r = const PngMinifier().minifyImage(image);
      expect(r.bitDepth, 16);
      expect(decode(r.bytes).sameAs(image), isTrue);
      expect(r.originalSize, image.pixelCount * 4);
    });

    test('a strategy set without reductions still works', () {
      final image = spriteImage(16, 16);
      final r = const PngMinifier(PngMinifyOptions(strategies: {}))
          .minifyImage(image);
      expect(r.colorType, PngColorType.rgba);
      expect(
        decode(r.bytes).sameAs(image, compareTransparentColor: true),
        isTrue,
      );
    });

    test('is deterministic', () {
      final input = plainPng(gradientImage(30, 30));
      final a = const PngMinifier().minify(input);
      final b = const PngMinifier().minify(input);
      expect(a.bytes, b.bytes);
      expect(a.strategy, b.strategy);
    });
  });

  group('PngMinifier lossy', () {
    test('a quality bound is never exceeded', () {
      final image = noisyImage(64, 64);
      final input = plainPng(image);
      for (final e in [4, 12, 30]) {
        for (final effort in PngEffort.values) {
          final r = PngMinifier(
            PngMinifyOptions(quality: PngQuality.maxError(e), effort: effort),
          ).minify(input);
          final diff = ImageDiff.of(image, decode(r.bytes));
          expect(
            diff.maxError,
            lessThanOrEqualTo(e),
            reason: 'e$e ${effort.name}',
          );
          expect(r.maxChannelError, diff.maxError);
          expect(r.changedPixels, diff.changedPixels);
        }
      }
    });

    test('lossy beats lossless on many-colour images', () {
      final input = plainPng(noisyImage(64, 64));
      final lossless = const PngMinifier().minify(input);
      final lossy = const PngMinifier(
        PngMinifyOptions(quality: PngQuality.maxError(24)),
      ).minify(input);
      expect(lossy.size, lessThan(lossless.size));
      expect(lossy.lossless, isFalse);
      expect(lossy.colorType, PngColorType.indexed);
    });

    test('PSNR quality holds', () {
      final image = gradientImage(64, 48);
      final r = const PngMinifier(
        PngMinifyOptions(quality: PngQuality.psnr(38), effort: PngEffort.max),
      ).minify(plainPng(image));
      final diff = ImageDiff.of(image, decode(r.bytes));
      expect(diff.psnrAtLeast(38), isTrue);
      expect(r.psnr, greaterThanOrEqualTo(38));
    });

    test('every lossy strategy can win on its own', () {
      final image = gradientImage(40, 40);
      final input = plainPng(image);
      for (final s in PngStrategy.values.where((s) => !s.isLossless)) {
        final r = PngMinifier(
          PngMinifyOptions(
            quality: const PngQuality.maxError(20),
            strategies: {
              s,
              PngStrategy.palette,
              PngStrategy.colorTypeReduction,
            },
            effort: PngEffort.max,
          ),
        ).minify(input);
        expect(
          ImageDiff.of(image, decode(r.bytes)).maxError,
          lessThanOrEqualTo(20),
          reason: s.name,
        );
      }
    });

    test('16-bit images may drop to 8 bits when lossy', () {
      final image = deepImage(16, 12);
      final r = const PngMinifier(
        PngMinifyOptions(quality: PngQuality.maxError(1)),
      ).minifyImage(image);
      expect(r.bitDepth, lessThanOrEqualTo(8));
      expect(r.lossless, isFalse);
    });

    test('presets produce valid output within their quality', () {
      final image = gradientImage(32, 32);
      final input = plainPng(image);
      for (final preset in PngPreset.values) {
        final r = PngMinifier.preset(preset).minify(input);
        final q = preset.options.quality;
        final diff = ImageDiff.of(image, decode(r.bytes));
        expect(
          diff.maxError,
          lessThanOrEqualTo(q.maxError),
          reason: preset.name,
        );
        if (q.minPsnr != null) {
          expect(diff.psnrAtLeast(q.minPsnr!), isTrue, reason: preset.name);
        }
      }
    });
  });

  group('PngMinifier metadata and special inputs', () {
    final text = PngChunk('tEXt', Uint8List.fromList(latin1.encode('k\x00v')));
    final gama = PngChunk('gAMA', Uint8List.fromList([0, 0, 0xb1, 0x8f]));
    final bkgd = PngChunk('bKGD', Uint8List(6));
    final priv = PngChunk('prVt', Uint8List(1));
    final unsafe = PngChunk('prVT', Uint8List(1));
    final input = plainPng(
      spriteImage(32, 32),
      ancillary: [text, gama, bkgd, priv, unsafe],
    );

    List<String> chunkTypes(Uint8List bytes) =>
        readPngChunks(bytes).map((c) => c.type).toList();

    test('color keeps only colour chunks (the default)', () {
      final r = const PngMinifier().minify(input);
      final types = chunkTypes(r.bytes);
      expect(types.take(2), ['IHDR', 'gAMA']);
      for (final dropped in ['tEXt', 'bKGD', 'prVt', 'prVT']) {
        expect(types, isNot(contains(dropped)));
      }
    });

    test('strip drops everything, all keeps the valid ones', () {
      final stripped = const PngMinifier(
        PngMinifyOptions(metadata: PngMetadata.strip),
      ).minify(input);
      expect(chunkTypes(stripped.bytes), isNot(contains('gAMA')));
      final all = const PngMinifier(PngMinifyOptions(metadata: PngMetadata.all))
          .minify(input);
      final types = chunkTypes(all.bytes);
      expect(types, containsAll(['tEXt', 'gAMA', 'prVt']));
      expect(types, isNot(contains('bKGD')));
      expect(types, isNot(contains('prVT')));
    });

    test('animated PNGs are returned unchanged', () {
      final apng = plainPng(
        spriteImage(8, 8),
        ancillary: [PngChunk('acTL', Uint8List(8))],
      );
      final r = const PngMinifier().minify(apng);
      expect(r.unchanged, isTrue);
      expect(r.reason, contains('APNG'));
      expect(r.bytes, apng);
    });

    test('invalid input throws PngFormatException', () {
      expect(
        () => const PngMinifier().minify(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<PngFormatException>()),
      );
    });

    test('verify can be turned off', () {
      final r = const PngMinifier(PngMinifyOptions(verify: false))
          .minify(input);
      expect(decode(r.bytes).width, 32);
    });
  });

  group('PngMinifyResult', () {
    test('toJson and toString', () {
      final r = const PngMinifier(
        PngMinifyOptions(quality: PngQuality.maxError(20)),
      ).minify(plainPng(noisyImage(24, 24)));
      final json = r.toJson();
      expect(json['size'], r.size);
      expect(json['strategy'], r.strategy);
      expect(json['psnr'], isA<double>());
      expect((json['candidates'] as List).length, r.candidates.length);
      expect(jsonEncode(json), isNotEmpty);
      expect(r.toString(), contains('max error'));
      expect(r.candidates.first.toString(), contains(':'));

      final lossless = const PngMinifier().minify(plainPng(spriteImage(9, 9)));
      expect(lossless.toJson()['psnr'], isNull);
      expect(lossless.toString(), contains('lossless'));
    });

    test('ratio of an empty original is 1', () {
      final r = PngMinifyResult(
        bytes: Uint8List(3),
        originalSize: 0,
        strategy: 's',
        lossless: true,
        changedPixels: 0,
        maxChannelError: 0,
        psnr: double.infinity,
        width: 1,
        height: 1,
        colorType: 6,
        bitDepth: 8,
      );
      expect(r.ratio, 1);
      expect(r.toJson().containsKey('reason'), isFalse);
    });
  });
}
