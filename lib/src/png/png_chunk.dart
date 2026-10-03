import 'dart:convert';
import 'dart:typed_data';

import 'crc32.dart';
import 'png_exception.dart';

/// The 8 bytes every PNG file starts with.
const List<int> pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/// One PNG chunk: a four-letter [type] and its [data].
class PngChunk {
  /// The chunk type, e.g. `IHDR`, `IDAT`, `tEXt`.
  final String type;

  /// The chunk payload (without length, type or CRC).
  final Uint8List data;

  /// Creates a chunk.
  PngChunk(this.type, this.data) {
    if (type.length != 4 || !_isTypeName(type)) {
      throw ArgumentError.value(type, 'type', 'not a PNG chunk type');
    }
  }

  /// Ancillary chunks (lowercase first letter) may be dropped by a decoder.
  bool get isCritical => _isUpper(type.codeUnitAt(0));

  /// Safe-to-copy chunks (lowercase fourth letter) may be kept by an editor
  /// that changed the image data.
  bool get isSafeToCopy => !_isUpper(type.codeUnitAt(3));

  @override
  String toString() => 'PngChunk($type, ${data.length} bytes)';
}

bool _isUpper(int c) => c >= 0x41 && c <= 0x5a;

bool _isTypeName(String type) =>
    type.codeUnits.every((c) => _isUpper(c) || (c >= 0x61 && c <= 0x7a));

/// Reads the chunks of [bytes], checking the signature and (when
/// [checkCrc]) every CRC. Stops after `IEND`.
List<PngChunk> readPngChunks(Uint8List bytes, {bool checkCrc = true}) {
  if (bytes.length < 8) {
    throw const PngFormatException('too short to be a PNG');
  }
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != pngSignature[i]) {
      throw const PngFormatException('missing PNG signature');
    }
  }
  final view = ByteData.sublistView(bytes);
  final chunks = <PngChunk>[];
  var pos = 8;
  while (true) {
    if (pos + 12 > bytes.length) {
      throw const PngFormatException('truncated chunk (no IEND)');
    }
    final length = view.getUint32(pos);
    if (length > 0x7fffffff || pos + 12 + length > bytes.length) {
      throw const PngFormatException('chunk length past the end of the file');
    }
    final typeBytes = bytes.sublist(pos + 4, pos + 8);
    final type = latin1.decode(typeBytes);
    if (!_isTypeName(type)) {
      throw PngFormatException('invalid chunk type "$type"');
    }
    final data = Uint8List.sublistView(bytes, pos + 8, pos + 8 + length);
    if (checkCrc) {
      final expected = view.getUint32(pos + 8 + length);
      final actual = crc32(data, crc32(typeBytes));
      if (expected != actual) {
        throw PngFormatException('bad CRC in $type chunk');
      }
    }
    chunks.add(PngChunk(type, data));
    pos += 12 + length;
    if (type == 'IEND') return chunks;
  }
}

/// Appends [chunk] (length, type, data, CRC) to [out].
void writePngChunk(BytesBuilder out, PngChunk chunk) {
  final header = ByteData(8)..setUint32(0, chunk.data.length);
  final typeBytes = latin1.encode(chunk.type);
  for (var i = 0; i < 4; i++) {
    header.setUint8(4 + i, typeBytes[i]);
  }
  out.add(header.buffer.asUint8List());
  out.add(chunk.data);
  final crc = ByteData(4)..setUint32(0, crc32(chunk.data, crc32(typeBytes)));
  out.add(crc.buffer.asUint8List());
}
