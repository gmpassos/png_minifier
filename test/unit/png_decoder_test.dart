import 'dart:typed_data';

import 'package:png_minifier/png_minifier.dart';
import 'package:png_minifier/src/png/png_chunk.dart';
import 'package:png_minifier/src/png/zlib.dart';
import 'package:test/test.dart';

import '../support/test_images.dart';

/// A PNG from raw parts, for malformed-input tests.
Uint8List rawPng({
  int width = 2,
  int height = 2,
  int bitDepth = 8,
  int colorType = PngColorType.rgba,
  int compression = 0,
  int interlace = 0,
  List<PngChunk> before = const [],
  List<int>? idat,
  bool withIdat = true,
  List<PngChunk> after = const [],
  bool ihdrFirst = true,
}) {
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, bitDepth)
    ..setUint8(9, colorType)
    ..setUint8(10, compression)
    ..setUint8(12, interlace);
  final rowBytes = PngRaster.rowBytesOf(width, colorType, bitDepth);
  final chunks = [
    if (!ihdrFirst) PngChunk('tEXt', Uint8List(1)),
    PngChunk('IHDR', ihdr.buffer.asUint8List()),
    ...before,
    if (withIdat)
      PngChunk(
        'IDAT',
        zlibCompress(idat ?? Uint8List((rowBytes + 1) * height)),
      ),
    ...after,
    PngChunk('IEND', Uint8List(0)),
  ];
  final out = BytesBuilder()..add(pngSignature);
  for (final c in chunks) {
    writePngChunk(out, c);
  }
  return out.takeBytes();
}

Matcher throwsFormat(String fragment) => throwsA(
  isA<PngFormatException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

void main() {
  const decoder = PngDecoder();

  group('PngDecoder', () {
    test('decodes what encodePng writes, for every representation', () {
      final image = spriteImage(17, 11, colors: 5);
      for (final colorType in [PngColorType.rgba, PngColorType.rgb]) {
        final channels = PngColorType.channels(colorType);
        final data = Uint8List(17 * 11 * channels);
        for (var i = 0; i < 17 * 11; i++) {
          for (var c = 0; c < channels; c++) {
            data[i * channels + c] = image.pixels[i * 4 + c];
          }
        }
        final png = encodePng(
          PngRaster(
            width: 17,
            height: 11,
            colorType: colorType,
            bitDepth: 8,
            data: data,
          ),
        );
        final decoded = decoder.decode(png);
        expect(decoded.colorType, colorType);
        expect(decoded.bitDepth, 8);
        expect(decoded.interlaced, isFalse);
        expect(decoded.animated, isFalse);
        for (var i = 0; i < 17 * 11; i++) {
          for (var c = 0; c < 3; c++) {
            expect(decoded.image.pixels[i * 4 + c], image.pixels[i * 4 + c]);
          }
          if (colorType == PngColorType.rgb) {
            expect(decoded.image.pixels[i * 4 + 3], 255);
          }
        }
      }
    });

    test('16-bit samples: kept when deep, dropped when exact in 8 bits', () {
      final deep = deepImage(5, 4);
      final data = Uint8List(5 * 4 * 8);
      for (var i = 0; i < deep.pixels16!.length; i++) {
        data[i * 2] = deep.pixels16![i] >> 8;
        data[i * 2 + 1] = deep.pixels16![i] & 0xff;
      }
      final png = encodePng(
        PngRaster(
          width: 5,
          height: 4,
          colorType: PngColorType.rgba,
          bitDepth: 16,
          data: data,
        ),
      );
      final decoded = decoder.decode(png).image;
      expect(decoded.isDeep, isTrue);
      expect(decoded.pixels16, deep.pixels16);
      expect(decoded.pixels, deep.pixels);

      // Every sample v·257: exactly representable in 8 bits.
      final shallow = Uint8List(5 * 4 * 8);
      for (var i = 0; i < shallow.length; i += 2) {
        shallow[i] = shallow[i + 1] = i & 0xff;
      }
      final png8 = encodePng(
        PngRaster(
          width: 5,
          height: 4,
          colorType: PngColorType.rgba,
          bitDepth: 16,
          data: shallow,
        ),
      );
      final d8 = decoder.decode(png8).image;
      expect(d8.isDeep, isFalse);
      expect(d8.pixels[0], 0);
      expect(d8.pixels[1], 2);
    });

    test('keeps ancillary chunks and flags APNG', () {
      final text = PngChunk('tEXt', Uint8List.fromList([65, 0, 66]));
      final actl = PngChunk('acTL', Uint8List(8));
      final decoded = decoder.decode(rawPng(before: [text, actl]));
      expect(decoded.ancillary.map((c) => c.type), ['tEXt', 'acTL']);
      expect(decoded.animated, isTrue);
    });

    test('rejects malformed headers', () {
      expect(
        () => decoder.decode(rawPng(ihdrFirst: false)),
        throwsFormat('IHDR'),
      );
      expect(() => decoder.decode(rawPng(width: 0)), throwsFormat('size'));
      expect(
        () => decoder.decode(rawPng(bitDepth: 3)),
        throwsFormat('bit depth'),
      );
      expect(
        () => decoder.decode(rawPng(compression: 1)),
        throwsFormat('compression'),
      );
      expect(
        () => decoder.decode(rawPng(interlace: 2)),
        throwsFormat('interlace'),
      );
      expect(
        () => const PngDecoder(maxPixels: 3).decode(rawPng()),
        throwsFormat('too large'),
      );
    });

    test('rejects malformed chunk sequences', () {
      final ihdr = PngChunk('IHDR', Uint8List(13));
      expect(
        () => decoder.decode(rawPng(before: [ihdr])),
        throwsFormat('duplicate IHDR'),
      );
      expect(
        () => decoder.decode(rawPng(before: [PngChunk('PLTE', Uint8List(4))])),
        throwsFormat('PLTE'),
      );
      expect(
        () => decoder.decode(rawPng(withIdat: false)),
        throwsFormat('IDAT'),
      );
      expect(
        () => decoder.decode(rawPng(before: [PngChunk('ABCD', Uint8List(0))])),
        throwsFormat('critical'),
      );
      expect(
        () => decoder.decode(rawPng(colorType: PngColorType.indexed)),
        throwsFormat('PLTE'),
      );
    });

    test('rejects bad image data', () {
      expect(
        () => decoder.decode(rawPng(idat: Uint8List(3))),
        throwsFormat('short'),
      );
      expect(
        () => decoder.decode(
          rawPng(
            colorType: PngColorType.indexed,
            width: 1,
            height: 1,
            before: [PngChunk('PLTE', Uint8List(3))],
            idat: [0, 7],
          ),
        ),
        throwsFormat('palette index'),
      );
    });
  });
}
