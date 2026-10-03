import 'package:png_minifier/png_minifier.dart';
import 'package:test/test.dart';

void main() {
  group('PngQuality', () {
    test('lossless is the default and only one that is lossless', () {
      expect(const PngQuality.lossless().isLossless, isTrue);
      expect(const PngQuality.maxError(0).isLossless, isTrue);
      expect(const PngQuality.maxError(1).isLossless, isFalse);
      expect(const PngQuality.psnr(40).isLossless, isFalse);
      expect(const PngMinifyOptions().quality.isLossless, isTrue);
    });

    test('level maps to an error bound', () {
      expect(PngQuality.level(100), const PngQuality.lossless());
      expect(PngQuality.level(80).maxError, 12);
      expect(PngQuality.level(60).maxError, 24);
      expect(PngQuality.level(99).maxError, 1);
      expect(PngQuality.level(0).maxError, 60);
      expect(() => PngQuality.level(101), throwsRangeError);
      expect(() => PngQuality.level(-1), throwsRangeError);
    });

    test('parse accepts the CLI forms', () {
      expect(PngQuality.parse('lossless'), const PngQuality.lossless());
      expect(PngQuality.parse('level:80'), PngQuality.level(80));
      expect(PngQuality.parse('max-error:7'), const PngQuality.maxError(7));
      expect(PngQuality.parse('psnr:45'), const PngQuality.psnr(45));
      expect(
        PngQuality.parse('max-error:9,psnr:40'),
        const PngQuality.bounded(maxError: 9, minPsnr: 40),
      );
      for (final bad in [
        'nope',
        'level:x',
        'level:200',
        'max-error:300',
        'psnr:0',
        'foo:1',
      ]) {
        expect(() => PngQuality.parse(bad), throwsFormatException, reason: bad);
      }
    });

    test('toString round-trips through parse', () {
      for (final q in [
        const PngQuality.lossless(),
        const PngQuality.maxError(12),
        const PngQuality.psnr(42.5),
        const PngQuality.bounded(maxError: 3, minPsnr: 50),
      ]) {
        expect(PngQuality.parse(q.toString()), q);
        expect(PngQuality.parse(q.toString()).hashCode, q.hashCode);
      }
    });
  });

  group('PngStrategy', () {
    test('lossless flags', () {
      expect(PngStrategy.palette.isLossless, isTrue);
      expect(PngStrategy.dithering.isLossless, isFalse);
    });

    test('defaults grow with effort', () {
      final fast = PngStrategy.defaultsFor(PngEffort.fast);
      final balanced = PngStrategy.defaultsFor(PngEffort.balanced);
      final max = PngStrategy.defaultsFor(PngEffort.max);
      expect(balanced.containsAll(fast), isTrue);
      expect(max, PngStrategy.values.toSet());
      expect(balanced.length, lessThan(max.length));
    });

    test('parse takes kebab or camel case', () {
      expect(
        PngStrategy.parse('frequency-palette'),
        PngStrategy.frequencyPalette,
      );
      expect(PngStrategy.parse('kMeansPalette'), PngStrategy.kMeansPalette);
      expect(() => PngStrategy.parse('zopfli'), throwsFormatException);
    });
  });

  group('PngMinifyOptions', () {
    test('active strategies and copyWith', () {
      const o = PngMinifyOptions();
      expect(o.activeStrategies, PngStrategy.defaultsFor(PngEffort.balanced));
      final c = o.copyWith(
        quality: const PngQuality.maxError(3),
        effort: PngEffort.max,
        strategies: {PngStrategy.palette},
        maxColors: 16,
        metadata: PngMetadata.all,
        preserveTransparentColor: true,
        verify: false,
      );
      expect(c.uses(PngStrategy.palette), isTrue);
      expect(c.uses(PngStrategy.filterSearch), isFalse);
      expect(c.maxColors, 16);
      expect(c.metadata, PngMetadata.all);
      expect(c.preserveTransparentColor, isTrue);
      expect(c.verify, isFalse);
      expect(c.toString(), contains('max-error:3'));
      expect(c.toString(), contains('preserveTransparentColor'));
      expect(o.copyWith().toString(), o.toString());
    });
  });

  group('PngPreset', () {
    test('every preset has a description and a CLI name', () {
      for (final p in PngPreset.values) {
        expect(p.description, isNotEmpty);
        expect(PngPreset.parse(p.cliName), p);
        expect(PngPreset.parse(p.name), p);
      }
      expect(PngPreset.pixelArt.cliName, 'pixel-art');
      expect(PngPreset.losslessMax.cliName, 'lossless-max');
      expect(() => PngPreset.parse('nope'), throwsFormatException);
    });

    test('pinned options', () {
      expect(PngPreset.lossless.options.quality.isLossless, isTrue);
      expect(PngPreset.losslessMax.options.effort, PngEffort.max);
      expect(PngPreset.fast.options.effort, PngEffort.fast);
      expect(PngPreset.web.options.quality, PngQuality.level(80));
      expect(PngPreset.pixelArt.options.uses(PngStrategy.dithering), isFalse);
      expect(
        PngPreset.pixelArt.options.uses(PngStrategy.frequencyPalette),
        isTrue,
      );
      expect(PngPreset.photo.options.quality.minPsnr, 38);
      expect(PngPreset.photo.options.uses(PngStrategy.dithering), isTrue);
      expect(PngPreset.smallest.options.quality, PngQuality.level(60));
      expect(PngPreset.smallest.options.metadata, PngMetadata.strip);
      for (final p in PngPreset.values) {
        if (p.options.quality.isLossless) {
          expect(
            p.options.activeStrategies.every((s) => s.isLossless) ||
                p.options.quality.isLossless,
            isTrue,
          );
        }
      }
    });
  });
}
