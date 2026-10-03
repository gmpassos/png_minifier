// Benchmarks png_minifier on public PNG datasets.
//
//   dart run tool/benchmark.dart                       # all datasets, default presets
//   dart run tool/benchmark.dart -d kodak -p lossless,photo
//   dart run tool/benchmark.dart -d path/to/pngs --json
//   dart run tool/benchmark.dart --make-fixtures       # rebuild test/fixtures/kodak
//
// Datasets are downloaded once into .benchmark/ (git-ignored):
//   kodak    — Kodak Lossless True Color Image Suite, 24 photos 768×512
//              (r0k.us; released by Kodak for unrestricted use), ~15 MB.
//   kenney   — Kenney CC0 game asset packs: Tiny Town, Pixel Platformer,
//              UI Pack (~1.7 MB zipped, ~7 MB unpacked; capped at 20 MB).
//   pngsuite — the committed PngSuite fixtures (test/fixtures/pngsuite).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:png_minifier/png_minifier.dart';

const _cache = '.benchmark';

/// The Kenney download must stay under this many bytes (zipped and
/// unpacked), as agreed for the dataset.
const _kenneyMaxBytes = 20 * 1024 * 1024;

const _kodakUrl = 'https://r0k.us/graphics/kodak/kodak';

const _kenneyPacks = {
  'tiny-town': 'https://kenney.nl/media/pages/assets/tiny-town/a415fbeb49-1735736916/kenney_tiny-town.zip',
  'pixel-platformer': 'https://kenney.nl/media/pages/assets/pixel-platformer/33bb4921eb-1696667883/kenney_pixel-platformer.zip',
  'ui-pack': 'https://kenney.nl/media/pages/assets/ui-pack/f651646eab-1718203990/kenney_ui-pack.zip',
};

// Kodak crops committed as photo fixtures: image, x, y, width, height.
const _kodakCrops = [
  ('kodim03', 280, 120, 192, 128), // caps: saturated flat colours
  ('kodim15', 300, 100, 192, 128), // face: smooth skin gradients
  ('kodim23', 360, 100, 192, 128), // parrots: fine detail
];

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'dataset',
      abbr: 'd',
      help: 'Comma-separated: kodak, kenney, pngsuite or a directory.',
      defaultsTo: 'pngsuite,kenney,kodak',
    )
    ..addOption(
      'preset',
      abbr: 'p',
      help: 'Comma-separated presets.',
      defaultsTo: 'fast,lossless,web,pixel-art,photo',
    )
    ..addFlag('json', negatable: false, help: 'Print JSON.')
    ..addFlag(
      'make-fixtures',
      negatable: false,
      help: 'Rebuild test/fixtures/kodak crops and exit.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final a = parser.parse(args);
  if (a.flag('help')) {
    print(parser.usage);
    return;
  }
  if (a.flag('make-fixtures')) {
    await _makeKodakFixtures();
    return;
  }

  final presets = [
    for (final p in a.option('preset')!.split(',')) PngPreset.parse(p.trim()),
  ];
  final rows = <Map<String, Object>>[];
  for (final name in a.option('dataset')!.split(',')) {
    final files = await _dataset(name.trim());
    for (final preset in presets) {
      rows.add(_run(name.trim(), files, preset));
      if (!a.flag('json')) _printRow(rows.last);
    }
  }
  if (a.flag('json')) {
    print(const JsonEncoder.withIndent('  ').convert(rows));
  }
}

Map<String, Object> _run(String dataset, List<File> files, PngPreset preset) {
  final minifier = PngMinifier.preset(preset);
  var count = 0, before = 0, after = 0, maxError = 0, failed = 0;
  var allLossless = true;
  final sw = Stopwatch()..start();
  for (final f in files) {
    final bytes = f.readAsBytesSync();
    try {
      final r = minifier.minify(bytes);
      count++;
      before += r.originalSize;
      after += r.size;
      if (r.maxChannelError > maxError) maxError = r.maxChannelError;
      allLossless &= r.lossless;
    } on PngFormatException {
      failed++; // PngSuite's deliberately corrupt files
    }
  }
  return {
    'dataset': dataset,
    'preset': preset.cliName,
    'files': count,
    'skipped': failed,
    'inputBytes': before,
    'outputBytes': after,
    'saved': before == 0 ? 0 : 1 - after / before,
    'lossless': allLossless,
    'maxError': maxError,
    'seconds': sw.elapsedMilliseconds / 1000,
  };
}

void _printRow(Map<String, Object> r) {
  String mb(Object b) => ((b as int) / 1048576).toStringAsFixed(2);
  print(
    '${(r['dataset'] as String).padRight(10)} '
    '${(r['preset'] as String).padRight(12)} '
    '${'${r['files']}'.padLeft(4)} files  '
    '${mb(r['inputBytes']!)} MB -> ${mb(r['outputBytes']!)} MB  '
    '${((r['saved'] as double) * 100).toStringAsFixed(1).padLeft(5)}% saved  '
    '${r['lossless'] == true ? 'lossless      ' : 'max error ${'${r['maxError']}'.padLeft(3)} '}'
    '${(r['seconds'] as double).toStringAsFixed(1).padLeft(6)} s',
  );
}

Future<List<File>> _dataset(String name) async {
  final Directory dir;
  switch (name) {
    case 'pngsuite':
      dir = Directory('test/fixtures/pngsuite');
    case 'kodak':
      dir = await _kodak();
    case 'kenney':
      dir = await _kenney();
    default:
      dir = Directory(name);
      if (!dir.existsSync()) {
        throw ArgumentError('unknown dataset or missing directory: $name');
      }
  }
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.png'))
      .toList()
    ..sort((x, y) => x.path.compareTo(y.path));
}

Future<Uint8List> _download(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    client.close();
  }
}

Future<Directory> _kodak() async {
  final dir = Directory('$_cache/kodak');
  dir.createSync(recursive: true);
  for (var i = 1; i <= 24; i++) {
    final name = 'kodim${i.toString().padLeft(2, '0')}.png';
    final file = File('${dir.path}/$name');
    if (file.existsSync() && file.lengthSync() > 0) continue;
    stderr.writeln('downloading $name');
    file.writeAsBytesSync(await _download('$_kodakUrl/$name'));
  }
  return dir;
}

Future<Directory> _kenney() async {
  final dir = Directory('$_cache/kenney');
  var total = 0;
  for (final MapEntry(key: pack, value: url) in _kenneyPacks.entries) {
    final packDir = Directory('${dir.path}/$pack');
    if (!packDir.existsSync()) {
      stderr.writeln('downloading Kenney $pack');
      final zip = await _download(url);
      total += zip.length;
      if (total > _kenneyMaxBytes) {
        throw StateError('Kenney download exceeds the 20 MB budget');
      }
      for (final entry in ZipDecoder().decodeBytes(zip)) {
        if (!entry.isFile) continue;
        final lower = entry.name.toLowerCase();
        if (!lower.endsWith('.png') && !lower.endsWith('license.txt')) {
          continue;
        }
        final out = File('${packDir.path}/${entry.name}');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(entry.content);
      }
    }
  }
  final unpacked = dir
      .listSync(recursive: true)
      .whereType<File>()
      .fold<int>(0, (sum, f) => sum + f.lengthSync());
  if (unpacked > _kenneyMaxBytes) {
    throw StateError(
      'Kenney dataset is ${unpacked ~/ 1048576} MB, over the 20 MB budget',
    );
  }
  return dir;
}

Future<void> _makeKodakFixtures() async {
  final source = await _kodak();
  final out = Directory('test/fixtures/kodak')..createSync(recursive: true);
  for (final (name, x0, y0, w, h) in _kodakCrops) {
    final image = const PngDecoder()
        .decode(File('${source.path}/$name.png').readAsBytesSync())
        .image;
    final rgb = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final s = ((y0 + y) * image.width + x0 + x) * 4;
        final d = (y * w + x) * 3;
        rgb[d] = image.pixels[s];
        rgb[d + 1] = image.pixels[s + 1];
        rgb[d + 2] = image.pixels[s + 2];
      }
    }
    // Stored plainly (no filter, fast deflate), like a typical export.
    final png = encodePng(
      PngRaster(
        width: w,
        height: h,
        colorType: PngColorType.rgb,
        bitDepth: 8,
        data: rgb,
      ),
      filter: PngFilterStrategy.none,
      level: 6,
    );
    File('${out.path}/${name}_crop.png').writeAsBytesSync(png);
    print('wrote ${out.path}/${name}_crop.png (${png.length} bytes)');
  }
}
