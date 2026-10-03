import 'dart:typed_data';

final Uint32List _table = _buildTable();

Uint32List _buildTable() {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c;
  }
  return table;
}

/// The CRC-32 (ISO 3309, as used by PNG chunks) of [bytes], continuing from
/// [crc] when the input arrives in parts.
int crc32(List<int> bytes, [int crc = 0]) {
  var c = crc ^ 0xffffffff;
  for (final b in bytes) {
    c = _table[(c ^ b) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}
