@Tags(['cli'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:png_minifier/png_minifier.dart';
import 'package:png_minifier/src/cli/png_minifier_cli.dart';
import 'package:test/test.dart';

import '../support/test_images.dart';

class Run {
  final int code;
  final String out;
  final String err;
  Run(this.code, this.out, this.err);
}

Run cli(List<String> args) {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = runPngMinifierCli(args, out: out, err: err);
  return Run(code, out.toString(), err.toString());
}

void main() {
  late Directory tmp;
  late String sprite;
  late String photo;
  final sep = Platform.pathSeparator;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('png_minifier_cli');
    sprite = '${tmp.path}${sep}sprite.png';
    photo = '${tmp.path}${sep}sub${sep}photo.PNG';
    File(sprite).writeAsBytesSync(plainPng(spriteImage(40, 30)));
    File(photo)
      ..createSync(recursive: true)
      ..writeAsBytesSync(plainPng(noisyImage(40, 30)));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('informational', () {
    test('--help, --version, --list-presets', () {
      expect(cli(['--help']).out, contains('Usage: png_minifier'));
      expect(cli(['--version']).out.trim(), 'png_minifier $pngMinifierVersion');
      final presets = cli(['--list-presets']).out;
      for (final p in PngPreset.values) {
        expect(presets, contains(p.cliName));
      }
    });

    test('usage errors exit 64', () {
      for (final args in [
        <String>[],
        ['--bogus', sprite],
        ['--preset', 'nope', sprite],
        ['--quality', 'level:500', sprite],
        ['--strategies', 'nope', sprite],
        ['--max-colors', '1', sprite],
        ['--in-place', '-o', 'x', sprite],
      ]) {
        final r = cli(args);
        expect(r.code, exitUsage, reason: '$args');
        expect(r.err, contains('png_minifier:'));
      }
    });
  });

  group('writing', () {
    test('default output is <name>.min.png next to the input', () {
      final r = cli([sprite]);
      expect(r.code, 0);
      expect(r.out, contains('lossless'));
      final out = File('${tmp.path}${sep}sprite.min.png');
      expect(out.lengthSync(), lessThan(File(sprite).lengthSync()));
      final image = const PngDecoder().decode(out.readAsBytesSync()).image;
      expect(image.sameAs(spriteImage(40, 30)), isTrue);
    });

    test('-o file for one input', () {
      final target = '${tmp.path}${sep}out.png';
      expect(cli(['-o', target, sprite]).code, 0);
      expect(File(target).existsSync(), isTrue);
    });

    test('-o directory mirrors a recursive tree', () {
      final outDir = '${tmp.path}${sep}out';
      final r = cli(['-r', '-o', outDir, tmp.path]);
      expect(r.code, 0);
      expect(File('$outDir${sep}sprite.png').existsSync(), isTrue);
      expect(File('$outDir${sep}sub${sep}photo.PNG').existsSync(), isTrue);
      expect(r.out, contains('total: 2 files'));
    });

    test('directories without -r skip subdirectories and .min.png', () {
      File('${tmp.path}${sep}old.min.png').writeAsBytesSync([1, 2, 3]);
      final r = cli(['--dry-run', tmp.path]);
      expect(r.code, 0);
      expect(r.out, contains('sprite.png'));
      expect(r.out, isNot(contains('photo')));
      expect(r.out, isNot(contains('old.min.png')));
    });

    test('--in-place overwrites only when smaller', () {
      final before = File(sprite).lengthSync();
      expect(cli(['--in-place', sprite]).code, 0);
      final after = File(sprite).lengthSync();
      expect(after, lessThan(before));
      final again = cli(['--in-place', sprite]);
      expect(again.out, contains('unchanged'));
      expect(File(sprite).lengthSync(), after);
    });

    test('--dry-run writes nothing', () {
      expect(cli(['-n', sprite]).code, 0);
      expect(File('${tmp.path}${sep}sprite.min.png').existsSync(), isFalse);
    });
  });

  group('options and reports', () {
    test('quality, effort, strategies, metadata and max colours apply', () {
      final r = cli([
        '--json',
        '-n',
        '-q',
        'max-error:20',
        '-e',
        'max',
        '--strategies',
        // Posterize always fits an error bound, so a lossy result exists.
        'palette,color-type-reduction,frequency-palette,posterize',
        '--max-colors',
        '64',
        '--metadata',
        'strip',
        '--preserve-transparent-color',
        photo,
      ]);
      expect(r.code, 0, reason: r.err);
      final report = jsonDecode(r.out) as List<Object?>;
      final entry = report.single as Map<String, Object?>;
      expect(entry['input'], photo);
      expect(entry['output'], isNull);
      expect(entry['lossless'], isFalse);
      expect(entry['maxChannelError'] as int, lessThanOrEqualTo(20));
      expect(entry['paletteSize'] as int? ?? 0, lessThanOrEqualTo(64));
      expect(entry['candidates'], isNotEmpty);
    });

    test('presets apply', () {
      final r = cli(['--json', '-n', '-p', 'pixel-art', photo]);
      final entry = (jsonDecode(r.out) as List).single as Map;
      expect(entry['maxChannelError'] as int, lessThanOrEqualTo(12));
    });

    test('bad and missing files fail with exit 1, others still run', () {
      final bad = '${tmp.path}${sep}bad.png';
      File(bad).writeAsStringSync('not a png');
      final r = cli(['-n', bad, '${tmp.path}${sep}missing.png', sprite]);
      expect(r.code, 1);
      expect(r.err, contains('bad.png'));
      expect(r.err, contains('missing.png'));
      expect(r.out, contains('sprite.png'));

      final json = cli(['-n', '--json', bad]);
      expect(json.code, 1);
      expect((jsonDecode(json.out) as List).single, containsPair('input', bad));
    });

    test('an empty directory is an error', () {
      final empty = Directory('${tmp.path}${sep}empty')..createSync();
      final r = cli([empty.path]);
      expect(r.code, 1);
      expect(r.err, contains('no PNG files'));
    });
  });

  test('runs as a real process', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/png_minifier.dart',
      '--json',
      '-n',
      sprite,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final entry = (jsonDecode(result.stdout as String) as List).single as Map;
    expect(entry['lossless'], isTrue);
    expect(entry['size'] as int, lessThan(entry['originalSize'] as int));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
