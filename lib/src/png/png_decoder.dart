import 'dart:typed_data';

import '../image/png_image.dart';
import 'png_chunk.dart';
import 'png_exception.dart';
import 'png_filters.dart';
import 'png_raster.dart';
import 'zlib.dart';

/// A decoded PNG: its pixels, how they were stored, and the ancillary
/// chunks the file carried.
class PngDecoded {
  /// The pixels.
  final PngImage image;

  /// The source colour type.
  final int colorType;

  /// The source bit depth.
  final int bitDepth;

  /// Whether the source was Adam7-interlaced.
  final bool interlaced;

  /// Ancillary chunks other than tRNS, in file order.
  final List<PngChunk> ancillary;

  /// True for an animated PNG (an `acTL` chunk): only its default image was
  /// decoded.
  final bool animated;

  /// Creates a decode result.
  PngDecoded({
    required this.image,
    required this.colorType,
    required this.bitDepth,
    required this.interlaced,
    required this.ancillary,
    required this.animated,
  });
}

/// Decodes every standard PNG: colour types 0, 2, 3, 4 and 6 at all their
/// bit depths, Adam7 interlacing, and tRNS transparency.
class PngDecoder {
  /// Verify chunk CRCs (on by default).
  final bool checkCrc;

  /// Refuse images with more pixels than this (a guard against bombs).
  final int maxPixels;

  /// Creates a decoder.
  const PngDecoder({this.checkCrc = true, this.maxPixels = 100000000});

  /// Decodes [bytes]; throws [PngFormatException] if they are not a valid PNG.
  PngDecoded decode(Uint8List bytes) {
    final chunks = readPngChunks(bytes, checkCrc: checkCrc);
    if (chunks.first.type != 'IHDR' || chunks.first.data.length != 13) {
      throw const PngFormatException('IHDR must be the first chunk');
    }
    final ihdr = ByteData.sublistView(chunks.first.data);
    final width = ihdr.getUint32(0);
    final height = ihdr.getUint32(4);
    final bitDepth = ihdr.getUint8(8);
    final colorType = ihdr.getUint8(9);
    final interlace = ihdr.getUint8(12);
    if (width == 0 ||
        height == 0 ||
        width > 0x7fffffff ||
        height > 0x7fffffff) {
      throw PngFormatException('invalid size ${width}x$height');
    }
    if (width * height > maxPixels) {
      throw PngFormatException('image too large: ${width}x$height');
    }
    if (!PngColorType.bitDepths(colorType).contains(bitDepth)) {
      throw PngFormatException(
        'invalid colour type $colorType / bit depth $bitDepth',
      );
    }
    if (ihdr.getUint8(10) != 0 || ihdr.getUint8(11) != 0 || interlace > 1) {
      throw const PngFormatException(
        'unknown compression, filter or '
        'interlace method',
      );
    }

    Uint8List? palette;
    Uint8List? trns;
    final idat = BytesBuilder(copy: false);
    final ancillary = <PngChunk>[];
    var animated = false;
    var sawIdat = false;
    for (final chunk in chunks.skip(1)) {
      switch (chunk.type) {
        case 'IHDR':
          throw const PngFormatException('duplicate IHDR');
        case 'PLTE':
          if (chunk.data.isEmpty ||
              chunk.data.length % 3 != 0 ||
              chunk.data.length > 768) {
            throw const PngFormatException('invalid PLTE length');
          }
          palette = chunk.data;
        case 'IDAT':
          sawIdat = true;
          idat.add(chunk.data);
        case 'IEND':
          break;
        case 'tRNS':
          trns = chunk.data;
        case 'acTL':
          animated = true;
          ancillary.add(chunk);
        default:
          if (chunk.isCritical) {
            throw PngFormatException('unknown critical chunk ${chunk.type}');
          }
          ancillary.add(chunk);
      }
    }
    if (!sawIdat) throw const PngFormatException('no IDAT chunk');
    if (colorType == PngColorType.indexed && palette == null) {
      throw const PngFormatException('indexed image without PLTE');
    }

    final raw = zlibDecompress(idat.takeBytes());
    final image = _Reader(
      width: width,
      height: height,
      colorType: colorType,
      bitDepth: bitDepth,
      palette: colorType == PngColorType.indexed ? palette : null,
      trns: trns,
    ).read(raw, interlace == 1);
    return PngDecoded(
      image: image,
      colorType: colorType,
      bitDepth: bitDepth,
      interlaced: interlace == 1,
      ancillary: ancillary,
      animated: animated,
    );
  }
}

// Adam7: x start, y start, x step, y step of the seven passes.
const _adam7 = [
  [0, 0, 8, 8],
  [4, 0, 8, 8],
  [0, 4, 4, 8],
  [2, 0, 4, 4],
  [0, 2, 2, 4],
  [1, 0, 2, 2],
  [0, 1, 1, 2],
];

class _Reader {
  final int width, height, colorType, bitDepth, channels;
  final Uint8List? palette;
  final Uint8List? trns;
  final Uint8List pixels;
  final Uint16List? samples16;
  int _greyKey = -1;
  int _rKey = -1, _gKey = -1, _bKey = -1;

  _Reader({
    required this.width,
    required this.height,
    required this.colorType,
    required this.bitDepth,
    required this.palette,
    required this.trns,
  }) : channels = PngColorType.channels(colorType),
       pixels = Uint8List(width * height * 4),
       samples16 = bitDepth == 16 ? Uint16List(width * height * 4) : null {
    final t = trns;
    if (t != null) {
      if (colorType == PngColorType.grey && t.length >= 2) {
        _greyKey = (t[0] << 8) | t[1];
      } else if (colorType == PngColorType.rgb && t.length >= 6) {
        _rKey = (t[0] << 8) | t[1];
        _gKey = (t[2] << 8) | t[3];
        _bKey = (t[4] << 8) | t[5];
      }
    }
  }

  PngImage read(Uint8List raw, bool interlaced) {
    final bpp = PngRaster.filterBppOf(colorType, bitDepth);
    var offset = 0;
    if (!interlaced) {
      final rowBytes = PngRaster.rowBytesOf(width, colorType, bitDepth);
      final rows = unfilterScanlines(raw, rowBytes, height, bpp);
      _store(rows, rowBytes, width, height, 0, 0, 1, 1);
    } else {
      for (final pass in _adam7) {
        final pw = (width - pass[0] + pass[2] - 1) ~/ pass[2];
        final ph = (height - pass[1] + pass[3] - 1) ~/ pass[3];
        if (pw <= 0 || ph <= 0) continue;
        final rowBytes = PngRaster.rowBytesOf(pw, colorType, bitDepth);
        final rows = unfilterScanlines(raw, rowBytes, ph, bpp, offset: offset);
        offset += (rowBytes + 1) * ph;
        _store(rows, rowBytes, pw, ph, pass[0], pass[1], pass[2], pass[3]);
      }
    }
    return PngImage(
      width,
      height,
      pixels,
      pixels16: samples16 != null && !_fitsEightBits(samples16!)
          ? samples16
          : null,
    );
  }

  static bool _fitsEightBits(Uint16List samples) {
    for (final v in samples) {
      if ((v >> 8) != (v & 0xff)) return false;
    }
    return true;
  }

  int _sample(Uint8List rows, int rowStart, int index) {
    switch (bitDepth) {
      case 8:
        return rows[rowStart + index];
      case 16:
        return (rows[rowStart + index * 2] << 8) |
            rows[rowStart + index * 2 + 1];
      default:
        final bit = index * bitDepth;
        final byte = rows[rowStart + (bit >> 3)];
        return (byte >> (8 - bitDepth - (bit & 7))) & ((1 << bitDepth) - 1);
    }
  }

  void _store(
    Uint8List rows,
    int rowBytes,
    int pw,
    int ph,
    int x0,
    int y0,
    int dx,
    int dy,
  ) {
    final maxValue = (1 << bitDepth) - 1;
    final pal = palette;
    final t = trns;
    for (var py = 0; py < ph; py++) {
      final rowStart = py * rowBytes;
      final y = y0 + py * dy;
      for (var px = 0; px < pw; px++) {
        final x = x0 + px * dx;
        final o = (y * width + x) * 4;
        int r, g, b, a;
        switch (colorType) {
          case PngColorType.grey:
            final v = _sample(rows, rowStart, px);
            r = g = b = v;
            a = v == _greyKey ? 0 : maxValue;
          case PngColorType.rgb:
            r = _sample(rows, rowStart, px * 3);
            g = _sample(rows, rowStart, px * 3 + 1);
            b = _sample(rows, rowStart, px * 3 + 2);
            a = r == _rKey && g == _gKey && b == _bKey ? 0 : maxValue;
          case PngColorType.indexed:
            final i = _sample(rows, rowStart, px);
            if (i * 3 + 2 >= pal!.length) {
              throw PngFormatException('palette index $i out of range');
            }
            r = pal[i * 3];
            g = pal[i * 3 + 1];
            b = pal[i * 3 + 2];
            a = t != null && i < t.length ? t[i] : 255;
            pixels[o] = r;
            pixels[o + 1] = g;
            pixels[o + 2] = b;
            pixels[o + 3] = a;
            continue;
          case PngColorType.greyAlpha:
            r = g = b = _sample(rows, rowStart, px * 2);
            a = _sample(rows, rowStart, px * 2 + 1);
          default:
            r = _sample(rows, rowStart, px * 4);
            g = _sample(rows, rowStart, px * 4 + 1);
            b = _sample(rows, rowStart, px * 4 + 2);
            a = _sample(rows, rowStart, px * 4 + 3);
        }
        final s16 = samples16;
        if (s16 != null) {
          s16[o] = r;
          s16[o + 1] = g;
          s16[o + 2] = b;
          s16[o + 3] = a;
          pixels[o] = _to8(r);
          pixels[o + 1] = _to8(g);
          pixels[o + 2] = _to8(b);
          pixels[o + 3] = _to8(a);
        } else if (bitDepth == 8) {
          pixels[o] = r;
          pixels[o + 1] = g;
          pixels[o + 2] = b;
          pixels[o + 3] = a;
        } else {
          pixels[o] = r * 255 ~/ maxValue;
          pixels[o + 1] = g * 255 ~/ maxValue;
          pixels[o + 2] = b * 255 ~/ maxValue;
          pixels[o + 3] = a * 255 ~/ maxValue;
        }
      }
    }
  }

  static int _to8(int v) => (v * 255 + 32767) ~/ 65535;
}
