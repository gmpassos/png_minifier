import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../api/png_minifier.dart';
import '../api/png_options.dart';
import '../api/png_preset.dart';
import '../api/png_quality.dart';
import '../api/png_result.dart';
import '../png/png_exception.dart';
import '../version.dart';

/// Exit code for bad command-line usage (BSD `EX_USAGE`).
const int exitUsage = 64;

ArgParser _parser() => ArgParser()
  ..addOption(
    'output',
    abbr: 'o',
    help:
        'Output file (one input) or directory. Default: <name>.min.png '
        'next to each input.',
  )
  ..addFlag(
    'in-place',
    abbr: 'i',
    negatable: false,
    help: 'Overwrite each input (only when the result is smaller).',
  )
  ..addOption(
    'preset',
    abbr: 'p',
    help: 'A preset (see --list-presets). Other options override its fields.',
    defaultsTo: 'lossless',
  )
  ..addOption(
    'quality',
    abbr: 'q',
    help:
        'lossless | level:0-100 | max-error:N | psnr:dB | max-error:N,psnr:dB',
  )
  ..addOption(
    'effort',
    abbr: 'e',
    allowed: [for (final e in PngEffort.values) e.name],
  )
  ..addOption(
    'strategies',
    help:
        'Comma-separated strategies, e.g. palette,filter-search,'
        'frequency-palette.',
  )
  ..addOption('max-colors', help: 'Palette size limit for lossy palettes.')
  ..addOption(
    'metadata',
    allowed: [for (final m in PngMetadata.values) m.name],
    help: 'Which ancillary chunks to keep.',
  )
  ..addFlag(
    'preserve-transparent-color',
    negatable: false,
    help: 'Keep the RGB of fully transparent pixels.',
  )
  ..addFlag(
    'recursive',
    abbr: 'r',
    negatable: false,
    help: 'Descend into subdirectories.',
  )
  ..addFlag(
    'dry-run',
    abbr: 'n',
    negatable: false,
    help: 'Report sizes, write nothing.',
  )
  ..addFlag('json', negatable: false, help: 'Print a JSON report.')
  ..addFlag('list-presets', negatable: false, help: 'List presets and exit.')
  ..addFlag('version', negatable: false, help: 'Print the version.')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

/// Runs the `png_minifier` command line with [args]; returns the exit code
/// (0 ok, 1 some file failed, 64 usage error).
int runPngMinifierCli(List<String> args, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final parser = _parser();
  final ArgResults a;
  final PngMinifyOptions options;
  try {
    a = parser.parse(args);
    if (a.flag('help')) {
      stdoutSink
        ..writeln('Minify PNG images: smaller files, same pixels by default.')
        ..writeln()
        ..writeln('Usage: png_minifier [options] <file|directory>...')
        ..writeln()
        ..writeln(parser.usage);
      return 0;
    }
    if (a.flag('version')) {
      stdoutSink.writeln('png_minifier $pngMinifierVersion');
      return 0;
    }
    if (a.flag('list-presets')) {
      for (final p in PngPreset.values) {
        stdoutSink.writeln('${p.cliName.padRight(13)} ${p.description}');
      }
      return 0;
    }
    options = _options(a);
    if (a.rest.isEmpty) {
      throw const FormatException('no input files');
    }
    if (a.flag('in-place') && a.option('output') != null) {
      throw const FormatException(
        '--in-place and --output exclude each '
        'other',
      );
    }
  } on FormatException catch (e) {
    stderrSink
      ..writeln('png_minifier: ${e.message}')
      ..writeln('Run "png_minifier --help" for usage.');
    return exitUsage;
  }

  final jobs = _jobs(a);
  if (jobs.isEmpty) {
    stderrSink.writeln('png_minifier: no PNG files found');
    return 1;
  }
  final minifier = PngMinifier(options);
  final dryRun = a.flag('dry-run');
  final json = a.flag('json');
  final report = <Map<String, Object?>>[];
  var failures = 0;
  var totalIn = 0;
  var totalOut = 0;
  for (final job in jobs) {
    try {
      final input = job.input.readAsBytesSync();
      final result = minifier.minify(input);
      totalIn += result.originalSize;
      totalOut += result.size;
      final write =
          !dryRun &&
          !(a.flag('in-place') && result.unchanged) &&
          job.output != null;
      if (write) {
        final target = job.output!;
        target.parent.createSync(recursive: true);
        target.writeAsBytesSync(result.bytes);
      }
      if (json) {
        report.add({
          'input': job.input.path,
          'output': write ? job.output!.path : null,
          ...result.toJson(),
        });
      } else {
        stdoutSink.writeln(_line(job.input.path, result));
      }
    } on PngFormatException catch (e) {
      failures++;
      _fail(json, report, stderrSink, job.input.path, e.message);
    } on FileSystemException catch (e) {
      failures++;
      _fail(json, report, stderrSink, job.input.path, e.message);
    }
  }
  if (json) {
    stdoutSink.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } else if (jobs.length > 1) {
    stdoutSink.writeln(
      'total: ${jobs.length - failures} files, ${_size(totalIn)} -> '
      '${_size(totalOut)} (${_percent(totalIn, totalOut)})',
    );
  }
  return failures == 0 ? 0 : 1;
}

void _fail(
  bool json,
  List<Map<String, Object?>> report,
  StringSink err,
  String path,
  String message,
) {
  if (json) report.add({'input': path, 'error': message});
  err.writeln('png_minifier: $path: $message');
}

PngMinifyOptions _options(ArgResults a) {
  var o = PngPreset.parse(a.option('preset')!).options;
  final quality = a.option('quality');
  if (quality != null) o = o.copyWith(quality: PngQuality.parse(quality));
  final effort = a.option('effort');
  if (effort != null) o = o.copyWith(effort: PngEffort.values.byName(effort));
  final strategies = a.option('strategies');
  if (strategies != null) {
    o = o.copyWith(
      strategies: {
        for (final s in strategies.split(','))
          if (s.trim().isNotEmpty) PngStrategy.parse(s.trim()),
      },
    );
  }
  final maxColors = a.option('max-colors');
  if (maxColors != null) {
    final n = int.tryParse(maxColors);
    if (n == null || n < 2 || n > 256) {
      throw const FormatException('--max-colors must be 2–256');
    }
    o = o.copyWith(maxColors: n);
  }
  final metadata = a.option('metadata');
  if (metadata != null) {
    o = o.copyWith(metadata: PngMetadata.values.byName(metadata));
  }
  if (a.flag('preserve-transparent-color')) {
    o = o.copyWith(preserveTransparentColor: true);
  }
  return o;
}

class _Job {
  final File input;
  final File? output;
  _Job(this.input, this.output);
}

bool _isPng(String path) => path.toLowerCase().endsWith('.png');

String _sep = Platform.pathSeparator;

String _minName(String path) => '${path.substring(0, path.length - 4)}.min.png';

List<_Job> _jobs(ArgResults a) {
  final output = a.option('output');
  final inPlace = a.flag('in-place');
  final recursive = a.flag('recursive');
  final jobs = <_Job>[];
  final singleFile =
      a.rest.length == 1 &&
      FileSystemEntity.isFileSync(a.rest.first) &&
      output != null &&
      _isPng(output) &&
      !FileSystemEntity.isDirectorySync(output);

  File? target(File input, String relative) {
    if (inPlace) return input;
    if (output == null) return File(_minName(input.path));
    if (singleFile) return File(output);
    return File('$output$_sep$relative');
  }

  for (final arg in a.rest) {
    if (FileSystemEntity.isDirectorySync(arg)) {
      final dir = Directory(arg);
      final files =
          dir
              .listSync(recursive: recursive)
              .whereType<File>()
              .where((f) => _isPng(f.path))
              .where((f) => !f.path.toLowerCase().endsWith('.min.png'))
              .toList()
            ..sort((x, y) => x.path.compareTo(y.path));
      for (final f in files) {
        final relative = f.path
            .substring(dir.path.length)
            .replaceFirst(RegExp(r'^[/\\]+'), '');
        jobs.add(_Job(f, target(f, relative)));
      }
    } else {
      // A missing file still becomes a job, so it is reported as failed.
      final f = File(arg);
      jobs.add(_Job(f, target(f, f.uri.pathSegments.last)));
    }
  }
  return jobs;
}

String _size(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(2)} MiB';

String _percent(int before, int after) {
  if (before == 0) return '0.0%';
  final p = (after - before) * 100 / before;
  return '${p > 0 ? '+' : ''}${p.toStringAsFixed(1)}%';
}

String _line(String path, PngMinifyResult r) {
  final quality = r.lossless
      ? 'lossless'
      : 'max error ${r.maxChannelError}, '
            'psnr ${r.psnr.toStringAsFixed(1)} dB';
  final how = r.unchanged ? 'unchanged (${r.reason})' : r.strategy;
  return '$path: ${_size(r.originalSize)} -> ${_size(r.size)} '
      '(${_percent(r.originalSize, r.size)}) $quality; $how';
}
