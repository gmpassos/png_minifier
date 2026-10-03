import 'dart:convert';
import 'dart:typed_data';

import 'package:png_minifier/png_minifier.dart';
import 'package:png_minifier/src/png/crc32.dart';
import 'package:png_minifier/src/png/png_chunk.dart';
import 'package:png_minifier/src/png/png_filters.dart';
import 'package:png_minifier/src/png/zlib.dart';
import 'package:test/test.dart';

import '../support/test_images.dart';

void main() {
  group('crc32', () {
    test('matches the standard check values', () {
      expect(crc32(ascii.encode('123456789')), 0xcbf43926);
      expect(crc32(const []), 0);
      expect(crc32(ascii.encode('IEND')), 0xae426082);
    });

    test('continues across parts', () {
      final whole = crc32(ascii.encode('hello world'));
      final parts = crc32(ascii.encode(' world'), crc32(ascii.encode('hello')));
      expect(parts, whole);
    });
  });

  group('PngChunk', () {
    test('rejects invalid types', () {
      expect(() => PngChunk('ab', Uint8List(0)), throwsArgumentError);
      expect(() => PngChunk('a1cd', Uint8List(0)), throwsArgumentError);
    });

    test('classifies critical and safe-to-copy chunks', () {
      expect(PngChunk('IDAT', Uint8List(0)).isCritical, isTrue);
      expect(PngChunk('tEXt', Uint8List(0)).isCritical, isFalse);
      expect(PngChunk('tEXt', Uint8List(0)).isSafeToCopy, isTrue);
      expect(PngChunk('gAMA', Uint8List(0)).isSafeToCopy, isFalse);
      expect(PngChunk('tEXt', Uint8List(3)).toString(), contains('tEXt'));
    });

    test('write then read round-trips', () {
      final out = BytesBuilder()..add(pngSignature);
      writePngChunk(out, PngChunk('tEXt', ascii.encode('a\x00b')));
      writePngChunk(out, PngChunk('IEND', Uint8List(0)));
      final chunks = readPngChunks(out.takeBytes());
      expect(chunks.map((c) => c.type), ['tEXt', 'IEND']);
      expect(ascii.decode(chunks.first.data), 'a\x00b');
    });

    test('reports structural errors', () {
      expect(
        () => readPngChunks(Uint8List(4)),
        throwsA(isA<PngFormatException>()),
      );
      expect(
        () => readPngChunks(Uint8List(16)),
        throwsA(isA<PngFormatException>()),
      );
      final noEnd = Uint8List.fromList([...pngSignature, 0, 0, 0]);
      expect(() => readPngChunks(noEnd), throwsA(isA<PngFormatException>()));

      final good = plainPng(spriteImage(8, 8));
      final badCrc = Uint8List.fromList(good)..[good.length - 1] ^= 0xff;
      expect(
        () => readPngChunks(badCrc),
        throwsA(
          isA<PngFormatException>().having(
            (e) => e.toString(),
            'message',
            contains('CRC'),
          ),
        ),
      );
      expect(readPngChunks(badCrc, checkCrc: false).last.type, 'IEND');

      final longLen = Uint8List.fromList(good)..[8] = 0x70;
      expect(() => readPngChunks(longLen), throwsA(isA<PngFormatException>()));

      final badType = Uint8List.fromList(good)..[12] = 0x31;
      expect(() => readPngChunks(badType), throwsA(isA<PngFormatException>()));
    });
  });

  group('zlib', () {
    test('round-trips and is deterministic', () {
      final data = Uint8List.fromList(List.generate(5000, (i) => i * 7 % 13));
      final a = zlibCompress(data);
      final b = zlibCompress(data);
      expect(a, b);
      expect(a.length, lessThan(data.length));
      expect(zlibDecompress(a), data);
      expect(zlibDecompress(zlibCompress(data, level: 1)), data);
    });

    test('corrupt streams throw PngFormatException', () {
      expect(
        () => zlibDecompress([0x78, 0x9c, 0xff, 0xff, 0xff, 0xff]),
        throwsA(isA<PngFormatException>()),
      );
    });
  });

  group('filters', () {
    final width = 13;
    final height = 9;
    for (final bpp in [1, 3, 4, 8]) {
      final rowBytes = width * bpp;
      final data = Uint8List.fromList(
        List.generate(rowBytes * height, (i) => (i * 31 + i ~/ 7) & 0xff),
      );
      for (final strategy in PngFilterStrategy.values) {
        test('${strategy.name} round-trips at bpp $bpp', () {
          final filtered = filterScanlines(
            data,
            rowBytes,
            height,
            bpp,
            strategy,
          );
          expect(filtered.length, (rowBytes + 1) * height);
          if (strategy.fixedType != null) {
            for (var y = 0; y < height; y++) {
              expect(filtered[y * (rowBytes + 1)], strategy.fixedType);
            }
          }
          expect(unfilterScanlines(filtered, rowBytes, height, bpp), data);
        });
      }
    }

    test('adaptive strategies pick per-row filters', () {
      // A vertical gradient: Up wins for every row after the first.
      final rowBytes = 32;
      final data = Uint8List(rowBytes * 8);
      for (var y = 0; y < 8; y++) {
        for (var i = 0; i < rowBytes; i++) {
          data[y * rowBytes + i] = (y * 20 + i * 3) & 0xff;
        }
      }
      final f = filterScanlines(data, rowBytes, 8, 1, PngFilterStrategy.minSum);
      expect(f[(rowBytes + 1) * 3], anyOf(2, 4));
    });

    test('rejects unknown filter types and short data', () {
      expect(
        () => unfilterScanlines(Uint8List.fromList([5, 0]), 1, 1, 1),
        throwsA(isA<PngFormatException>()),
      );
      expect(
        () => unfilterScanlines(Uint8List(3), 4, 1, 1),
        throwsA(isA<PngFormatException>()),
      );
    });
  });

  group('PngRaster', () {
    test('validates depth, length and palette', () {
      expect(
        () => PngRaster(
          width: 2,
          height: 1,
          colorType: PngColorType.rgb,
          bitDepth: 4,
          data: Uint8List(1),
        ),
        throwsArgumentError,
      );
      expect(
        () => PngRaster(
          width: 2,
          height: 1,
          colorType: PngColorType.rgb,
          bitDepth: 8,
          data: Uint8List(5),
        ),
        throwsArgumentError,
      );
      expect(
        () => PngRaster(
          width: 2,
          height: 1,
          colorType: PngColorType.indexed,
          bitDepth: 8,
          data: Uint8List(2),
        ),
        throwsArgumentError,
      );
    });

    test('computes row bytes, filter distance and labels', () {
      expect(PngRaster.rowBytesOf(3, PngColorType.grey, 1), 1);
      expect(PngRaster.rowBytesOf(9, PngColorType.grey, 1), 2);
      expect(PngRaster.rowBytesOf(3, PngColorType.rgba, 16), 24);
      expect(PngRaster.filterBppOf(PngColorType.indexed, 4), 1);
      expect(PngRaster.filterBppOf(PngColorType.rgb, 16), 6);
      expect(PngColorType.name(PngColorType.greyAlpha), 'grey+alpha');
      expect(PngColorType.name(9), 'unknown');
      expect(() => PngColorType.channels(5), throwsArgumentError);
      expect(PngColorType.bitDepths(1), isEmpty);
    });
  });
}
