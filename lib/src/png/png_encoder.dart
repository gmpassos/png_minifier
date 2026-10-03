import 'dart:typed_data';

import 'png_chunk.dart';
import 'png_filters.dart';
import 'png_raster.dart';
import 'zlib.dart';

/// Filters [raster] with [filter], compresses it with deflate [level] and
/// returns a complete PNG file. [ancillary] chunks are written right after
/// IHDR (before PLTE and IDAT, which every ancillary chunk may precede).
Uint8List encodePng(
  PngRaster raster, {
  PngFilterStrategy filter = PngFilterStrategy.minSum,
  int level = 9,
  List<PngChunk> ancillary = const [],
}) {
  final idat = compressRaster(raster, filter: filter, level: level);
  return assemblePng(raster, idat, ancillary: ancillary);
}

/// The IDAT payload of [raster]: filtered scanlines, zlib-compressed.
Uint8List compressRaster(
  PngRaster raster, {
  required PngFilterStrategy filter,
  required int level,
}) {
  final filtered = filterScanlines(
    raster.data,
    raster.rowBytes,
    raster.height,
    raster.filterBpp,
    filter,
  );
  return zlibCompress(filtered, level: level);
}

/// A PNG file from [raster]'s header chunks and an already compressed [idat].
Uint8List assemblePng(
  PngRaster raster,
  Uint8List idat, {
  List<PngChunk> ancillary = const [],
}) {
  final out = BytesBuilder(copy: false)..add(pngSignature);
  final ihdr = ByteData(13)
    ..setUint32(0, raster.width)
    ..setUint32(4, raster.height)
    ..setUint8(8, raster.bitDepth)
    ..setUint8(9, raster.colorType);
  writePngChunk(out, PngChunk('IHDR', ihdr.buffer.asUint8List()));
  for (final chunk in ancillary) {
    writePngChunk(out, chunk);
  }
  final palette = raster.palette;
  if (palette != null) writePngChunk(out, PngChunk('PLTE', palette));
  final trns = raster.transparency;
  if (trns != null) writePngChunk(out, PngChunk('tRNS', trns));
  writePngChunk(out, PngChunk('IDAT', idat));
  writePngChunk(out, PngChunk('IEND', Uint8List(0)));
  return out.takeBytes();
}
