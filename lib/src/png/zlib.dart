import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'png_exception.dart';

// The pure-Dart codecs on purpose: archive's `ZLibEncoder` switches to the
// native zlib on the VM, whose output differs from the Dart implementation
// used on the web. One implementation everywhere keeps the minified bytes
// identical on the VM, dart2js and dart2wasm.
const _encoder = ZLibEncoderWeb();
const _decoder = ZLibDecoderWeb();

/// Compresses [data] in the zlib format at deflate [level] (0–9).
Uint8List zlibCompress(List<int> data, {int level = 9}) =>
    _encoder.encodeBytes(data, level: level);

/// Decompresses a zlib stream, checking its Adler-32.
Uint8List zlibDecompress(List<int> data) {
  try {
    return _decoder.decodeBytes(data, verify: true);
  } on PngFormatException {
    rethrow;
  } catch (e) {
    throw PngFormatException('corrupt image data: $e');
  }
}
