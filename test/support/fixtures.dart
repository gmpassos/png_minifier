import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:png_minifier/png_minifier.dart';

/// The committed fixture PNGs of [dir] (under test/fixtures), sorted.
List<File> fixtures(String dir) =>
    Directory('test/fixtures/$dir')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// The file name of [f].
String nameOf(File f) => f.uri.pathSegments.last;

/// [bytes] decoded by package:image — an independent decoder — as 16-bit
/// RGBA samples (8-bit sources scaled by 257, low depths to full range), so
/// it compares with [PngImage.pixels16] or `pixels × 257`.
Uint16List oracleRgba16(Uint8List bytes) {
  final image = img.decodePng(bytes)!;
  final out = Uint16List(image.width * image.height * 4);
  // Palette entries are 8-bit whatever the index depth.
  final max = image.hasPalette ? 255 : image.maxChannelValue.toInt();
  int scale(num v) => (v.toInt() * 65535 + max ~/ 2) ~/ max;
  // Without a palette, one channel is grey and two are grey+alpha
  // (package:image reports g and b as 0 for a one-channel image).
  final grey = !image.hasPalette && image.numChannels <= 2;
  // A palette without alpha is opaque (package:image reports alpha 0 for
  // sub-byte indices into an RGB palette).
  final opaquePalette = image.hasPalette && image.palette!.numChannels < 4;
  var o = 0;
  for (final p in image) {
    final r = scale(p.r);
    out[o++] = r;
    out[o++] = grey ? r : scale(p.g);
    out[o++] = grey ? r : scale(p.b);
    out[o++] = opaquePalette ? 65535 : scale(p.a);
  }
  return out;
}

/// [image] as 16-bit RGBA samples (its own 16-bit data, or 8-bit × 257).
Uint16List rgba16Of(PngImage image) =>
    image.pixels16 ??
    Uint16List.fromList([for (final v in image.pixels) v * 257]);

/// Whether two 16-bit RGBA buffers show the same pixels (the colour of
/// fully transparent pixels is ignored).
bool sameVisible16(Uint16List a, Uint16List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i + 3] != b[i + 3]) return false;
    if (a[i + 3] == 0) continue;
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
      return false;
    }
  }
  return true;
}
