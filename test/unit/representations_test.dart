import 'dart:typed_data';

import 'package:png_minifier/png_minifier.dart';
import 'package:png_minifier/src/image/color.dart';
import 'package:png_minifier/src/image/color_histogram.dart';
import 'package:png_minifier/src/optimize/palette_order.dart';
import 'package:png_minifier/src/optimize/representations.dart';
import 'package:png_minifier/src/quantize/posterize.dart';
import 'package:test/test.dart';

import '../support/test_images.dart';

/// Encodes every representation and checks each decodes to [image].
List<PngRaster> checkAll(
  PngImage image, {
  bool preserve = false,
  Set<PaletteOrder> orders = const {PaletteOrder.frequency},
}) {
  final rasters = buildRepresentations(
    image,
    ColorHistogram.of(image),
    orders: orders,
    preserveTransparentColor: preserve,
  );
  for (final r in rasters) {
    final decoded = const PngDecoder().decode(encodePng(r)).image;
    expect(
      decoded.sameAs(image, compareTransparentColor: preserve),
      isTrue,
      reason: r.label,
    );
  }
  return rasters;
}

PngImage solid(int w, int h, List<int> rgba) => PngImage(
  w,
  h,
  Uint8List.fromList([for (var i = 0; i < w * h; i++) ...rgba]),
);

void main() {
  group('buildRepresentations', () {
    test('two-colour opaque art: 1-bit palette and 1-bit grey', () {
      final p = Uint8List(8 * 8 * 4);
      for (var i = 0; i < 64; i++) {
        final v = i.isEven ? 255 : 0;
        p[i * 4] = p[i * 4 + 1] = p[i * 4 + 2] = v;
        p[i * 4 + 3] = 255;
      }
      final labels = checkAll(PngImage(8, 8, p)).map((r) => r.label).toList();
      expect(labels, containsAll(['palette1(frequency)', 'grey1', 'rgb8']));
      expect(labels.last, 'rgba8');
    });

    test('grey depths follow the levels used', () {
      String greyLabel(int step) =>
          checkAll(greyImage(9, 7, step: step))
              .map((r) => r.label)
              .firstWhere((l) => l.startsWith('grey'));
      expect(greyLabel(85), 'grey2');
      expect(greyLabel(17), 'grey4');
      expect(greyLabel(1), 'grey8');
    });

    test('sprites on transparency get a colour key', () {
      final image = clearTransparent(spriteImage(12, 10, colors: 3));
      final labels = checkAll(image).map((r) => r.label);
      expect(labels, contains('rgb8+key'));
      // Three colours plus transparent: a 2-bit palette.
      expect(labels, contains('palette2(frequency)'));
    });

    test('grey with transparency: key, then grey+alpha', () {
      final p = Uint8List(4 * 4 * 4);
      for (var i = 0; i < 16; i++) {
        p[i * 4] = p[i * 4 + 1] = p[i * 4 + 2] = i < 8 ? 0 : 255;
        p[i * 4 + 3] = i % 4 == 0 ? 0 : 255;
      }
      final image = clearTransparent(PngImage(4, 4, p));
      final labels = checkAll(image).map((r) => r.label);
      expect(labels, contains('grey2+key'));
      expect(labels, contains('grey+alpha8'));
    });

    test('preserved transparent colour: a key only when it is unique', () {
      final coloured = spriteImage(
        10,
        10,
        colors: 3,
        colouredTransparency: true,
      );
      final labels = checkAll(coloured, preserve: true).map((r) => r.label);
      expect(labels.where((l) => l.contains('key')), isEmpty);

      final p = Uint8List.fromList(solid(3, 1, [9, 9, 9, 255]).pixels)
        ..setAll(0, [200, 100, 50, 0]);
      final single = PngImage(3, 1, p);
      expect(
        checkAll(single, preserve: true).map((r) => r.label),
        contains('rgb8+key'),
      );

      final greyKey = PngImage(
        3,
        1,
        Uint8List.fromList([17, 17, 17, 0, 34, 34, 34, 255, 51, 51, 51, 255]),
      );
      expect(
        checkAll(greyKey, preserve: true).map((r) => r.label),
        contains('grey4+key'),
      );
    });

    test('partial alpha: grey+alpha or RGBA, palette with tRNS', () {
      final rasters = checkAll(gradientImage(6, 5));
      expect(rasters.map((r) => r.label), contains('rgba8'));
      final grey = PngImage(
        2,
        1,
        Uint8List.fromList([10, 10, 10, 100, 20, 20, 20, 200]),
      );
      final labels = checkAll(grey).map((r) => r.label);
      expect(labels, contains('grey+alpha8'));
      final pal = checkAll(grey)
          .firstWhere((r) => r.colorType == PngColorType.indexed);
      expect(pal.transparency, [100, 200]);
    });

    test('a palette is skipped above 256 colours', () {
      final labels = checkAll(noisyImage(40, 40)).map((r) => r.label);
      expect(labels.where((l) => l.startsWith('palette')), isEmpty);
      expect(labels, contains('rgb8'));
    });

    test('options switch representations off', () {
      final image = spriteImage(8, 8, colors: 3);
      final only = buildRepresentations(
        image,
        ColorHistogram.of(image),
        reduceColorType: false,
        palette: false,
      );
      expect(only.map((r) => r.label), ['rgba8']);
    });

    test('16-bit images keep 16-bit representations', () {
      expect(checkAll(deepImage(4, 3)).map((r) => r.label), ['rgba16']);
      expect(checkAll(deepImage(4, 3, opaque: true)).map((r) => r.label), [
        'rgb16',
        'rgba16',
      ]);
      final s = Uint16List(4 * 4);
      final p = Uint8List(4 * 4);
      for (var i = 0; i < 4; i++) {
        s[i * 4] = s[i * 4 + 1] = s[i * 4 + 2] = 1000 * i + 1;
        s[i * 4 + 3] = 0xffff;
        p[i * 4] = p[i * 4 + 1] = p[i * 4 + 2] =
            (s[i * 4] * 255 + 32767) ~/ 65535;
        p[i * 4 + 3] = 255;
      }
      final greyDeep = PngImage(4, 1, p, pixels16: s);
      expect(checkAll(greyDeep).map((r) => r.label), [
        'grey16',
        'grey+alpha16',
        'rgb16',
        'rgba16',
      ]);
    });
  });

  group('orderPalette', () {
    final image = PngImage(
      5,
      1,
      Uint8List.fromList([
        ...[200, 200, 200, 255],
        ...[10, 10, 10, 255],
        ...[10, 10, 10, 255],
        ...[100, 100, 100, 128],
        ...[90, 90, 90, 255],
      ]),
    );
    final h = ColorHistogram.of(image);

    test('translucent entries first in every order', () {
      for (final order in PaletteOrder.values) {
        expect(alphaOf(orderPalette(h, order).first), 128, reason: order.name);
      }
    });

    test('frequency, luma and neighbour orders', () {
      expect(
        orderPalette(h, PaletteOrder.frequency)[1],
        packRgba(10, 10, 10, 255),
      );
      expect(orderPalette(h, PaletteOrder.luma).skip(1).map(redOf), [
        10,
        90,
        200,
      ]);
      expect(orderPalette(h, PaletteOrder.neighbour).skip(1).map(redOf), [
        10,
        90,
        200,
      ]);
    });
  });
}
