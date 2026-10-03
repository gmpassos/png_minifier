# png_minifier

[![pub package](https://img.shields.io/pub/v/png_minifier.svg?logo=dart&logoColor=00b9fc)](https://pub.dev/packages/png_minifier)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Dart CI](https://github.com/gmpassos/png_minifier/actions/workflows/dart.yml/badge.svg?branch=main)](https://github.com/gmpassos/png_minifier/actions/workflows/dart.yml)
[![codecov](https://codecov.io/gh/gmpassos/png_minifier/branch/main/graph/badge.svg)](https://codecov.io/gh/gmpassos/png_minifier)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/png_minifier?logo=git&logoColor=white)](https://github.com/gmpassos/png_minifier/releases)
[![New Commits](https://img.shields.io/github/commits-since/gmpassos/png_minifier/latest?logo=git&logoColor=white)](https://github.com/gmpassos/png_minifier/network)
[![Last Commits](https://img.shields.io/github/last-commit/gmpassos/png_minifier?logo=git&logoColor=white)](https://github.com/gmpassos/png_minifier/commits/main)
[![Pull Requests](https://img.shields.io/github/issues-pr/gmpassos/png_minifier?logo=github&logoColor=white)](https://github.com/gmpassos/png_minifier/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/gmpassos/png_minifier?logo=github&logoColor=white)](https://github.com/gmpassos/png_minifier)
[![License](https://img.shields.io/github/license/gmpassos/png_minifier?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/png_minifier/blob/main/LICENSE)

Minify PNG images in pure Dart: fewer bytes, **the same pixels** by default —
or a quality bound you choose.

There is no single best way to shrink a PNG: the right colour type, palette,
filter and compression depend on the image. `png_minifier` lets many
optimisation **strategies** propose candidate encodings, rejects any that
break the quality target, and keeps the **smallest**. If nothing beats the
input, you get the input back.

It runs anywhere Dart runs — VM, Flutter, dart2js and dart2wasm — with no
native code, and the output is **byte-identical on every platform**, so a
build that minifies assets is reproducible.

## API Documentation

See the [API Documentation][api_doc] for the full list of classes and
options.

[api_doc]: https://pub.dev/documentation/png_minifier/latest/

## Features

- **Lossless by default** — the decoded pixels are identical (the colour of
  fully transparent pixels, which nobody can see, may change unless you ask
  to keep it).
- **Custom quality** — a per-channel error bound, a minimum PSNR, both, or a
  TinyPNG-like `level` from 0 to 100. Every lossy candidate is measured
  against it before it may win.
- **Many strategies**:
  - lossless: transparent-pixel cleanup; colour-type and bit-depth reduction
    (RGB, greyscale at 1/2/4/8/16 bits, grey+alpha, tRNS colour keys);
    indexed palettes at 1/2/4/8 bits in three orders; seven PNG filter
    strategies; deflate-level search;
  - lossy: a frequency palette for pixel art (popular colours stay exact),
    median cut, k-means, Floyd–Steinberg dithering that never leaves the
    error bound, posterize, alpha snapping.
- **Presets** for common jobs, from `fast` to `smallest`.
- **Effort levels**: `fast`, `balanced`, `max`.
- **Metadata**: strip it, keep only colour chunks (the default), or keep all
  that stay valid.
- A complete **PNG decoder** (every colour type and bit depth, Adam7,
  transparency, CRC checks) and encoder.
- A **command line** tool for files and whole directories.

## How it works

1. **Decode** the PNG to RGBA (keeping 16-bit samples when they carry more
   than 8 bits).
2. **Transform**: the exact image (with invisible pixels normalised) and —
   when the quality allows — the lossy candidates: quantised palettes,
   dithered, posterized, alpha-snapped. Each lossy image is compared with
   the original and dropped if it breaks the quality.
3. **Represent** each image in every PNG form that holds it exactly:
   palette (several orders), greyscale, colour key, RGB, RGBA.
4. **Compress** each representation with each filter strategy at a quick
   deflate level; the most promising few are recompressed at full effort.
5. **Judge**: the smallest file wins (ties go to the first tried, so the
   result is deterministic). It is decoded once more and checked against
   the expected pixels before it is returned.

Errors are measured on the *visible* colour: alpha and premultiplied RGB,
per channel, on the 0–255 scale. A pixel at 2% opacity can change colour a
lot without anyone noticing; an opaque one cannot.

## Getting started

```shell
dart pub add png_minifier
```

Or, for the command line:

```shell
dart pub global activate png_minifier
```

## Usage

### Lossless (the default)

```dart
import 'dart:io';

import 'package:png_minifier/png_minifier.dart';

void main() {
  final input = File('image.png').readAsBytesSync();
  final result = const PngMinifier().minify(input);

  print('${result.originalSize} -> ${result.size} bytes '
      '(${result.strategy})');
  File('image.min.png').writeAsBytesSync(result.bytes);
}
```

### Presets

```dart
final sprite = PngMinifier.preset(PngPreset.pixelArt).minify(input);
final photo = PngMinifier.preset(PngPreset.photo).minify(input);
```

| Preset | Quality | Effort | For |
|---|---|---|---|
| `lossless` (default) | pixel-identical | balanced | everyday use |
| `losslessMax` | pixel-identical | max | release builds, asset bakes |
| `fast` | pixel-identical | fast | dev loops, big batches |
| `web` | level 80 (error ≤ 12) | balanced | general web images |
| `pixelArt` | error ≤ 12, frequency palette, no dithering | max | sprites, tiles, atlases |
| `photo` | PSNR ≥ 38 dB, median cut, k-means, dithering | balanced | photographs |
| `smallest` | level 60 (error ≤ 24), metadata stripped | max | when size matters most |

### Custom quality and options

```dart
final result = const PngMinifier(PngMinifyOptions(
  quality: PngQuality.maxError(8), // or .psnr(42), .level(85), .bounded(...)
  effort: PngEffort.max,
  metadata: PngMetadata.strip,
  maxColors: 128,
)).minify(input);

print(result.lossless);        // false
print(result.maxChannelError); // ≤ 8
print(result.psnr);            // dB
```

Start from a preset and change one thing:

```dart
final options = PngPreset.web.options.copyWith(effort: PngEffort.max);
```

Choose the strategies yourself:

```dart
const options = PngMinifyOptions(
  quality: PngQuality.maxError(12),
  strategies: {
    PngStrategy.colorTypeReduction,
    PngStrategy.palette,
    PngStrategy.filterSearch,
    PngStrategy.frequencyPalette,
  },
);
```

### From pixels

When you already hold pixels (a game's sprite baker, a canvas), skip the
decode:

```dart
final image = PngImage.fromArgb(width, height, argbPixels);
final png = const PngMinifier().minifyImage(image).bytes;
```

### What was tried

```dart
for (final candidate in result.candidates) {
  print('${candidate.name}: ${candidate.size}');
}
```

For a 192×128 Kodak photo crop (39,667 bytes) with the `pixelArt` preset:

```text
exact/rgb8/none/z6: 39667
exact/rgb8/sub/z6: 41023
…
frequency(e12)/palette8(frequency)/none/z6: 11631
frequency(e12)/palette8(frequency)/sub/z6: 13193
…
frequency(e12)/palette8(frequency)/none/z9: 11624   ← the winner
```

Each name reads `<image>/<representation>/<filter>/z<deflate level>`.

## Command line

```text
png_minifier [options] <file|directory>...

  -o, --output        Output file (one input) or directory.
                      Default: <name>.min.png next to each input.
  -i, --in-place      Overwrite each input (only when the result is smaller).
  -p, --preset        lossless | lossless-max | fast | web | pixel-art |
                      photo | smallest  (default: lossless)
  -q, --quality       lossless | level:0-100 | max-error:N | psnr:dB
  -e, --effort        fast | balanced | max
      --strategies    Comma-separated strategies.
      --max-colors    Palette size limit for lossy palettes.
      --metadata      strip | color | all
  -r, --recursive     Descend into subdirectories.
  -n, --dry-run       Report sizes, write nothing.
      --json          Print a JSON report.
      --list-presets  List presets and exit.
```

```shell
# Same pixels, in place, a whole asset tree:
png_minifier -r --in-place assets/

# TinyPNG-like, into another directory:
png_minifier -p web -r -o build/assets assets/

# How much would pixel-art quantisation save? Write nothing:
png_minifier -p pixel-art -n --json sprites/
```

Exit codes: `0` success, `1` some file could not be read or decoded, `64`
bad usage.

## Benchmarks

`tool/benchmark.dart` runs the presets over public datasets (downloaded on
first use into `.benchmark/`). Saved bytes, and the largest per-channel
error of any pixel (`0` = lossless):

| Preset | PngSuite (162 files, 0.11 MB) | Kenney CC0 packs (1,246 files, 0.97 MB) | Kodak photos (24 files, 14.7 MB) |
|---|---|---|---|
| `fast` | 32.6% · 0 | 2.1% · 0 | 0.2% · 0 |
| `lossless` | 37.8% · 0 | 2.7% · 0 | 0.2% · 0 |
| `losslessMax` | 39.3% · 0 | 2.9% · 0 | 0.3% · 0 |
| `web` | 47.7% · 12 | 2.7% · 0 | 23.5% · 12 |
| `pixelArt` | 48.6% · 12 | 2.9% · 0 | 22.8% · 12 |
| `photo` | 47.8% · 32 | 2.7% · 0 | 48.0% · 48 (PSNR ≥ 38 dB) |
| `smallest` | 68.8% · 24 | 33.1% · 24 | 87.1% · 24 |

The Kenney packs and the Kodak PNGs are already well optimised, so the
lossless presets find little to remove there; the gains come from images
saved as plain RGBA by typical exporters. On Kenney art, the lossy presets
only win at `smallest`: their palettes are already exact. `photo` bounds
PSNR rather than per-pixel error, so single pixels may move more.

Run them yourself:

```shell
dart run tool/benchmark.dart                         # all datasets
dart run tool/benchmark.dart -d kodak -p lossless,photo
dart run tool/benchmark.dart -d path/to/your/pngs --json
```

## Running the example and tests

```shell
dart pub get
dart analyze
dart test                                   # VM: unit, integration, CLI, golden
dart test -p chrome                         # dart2js
dart test -p chrome -c dart2wasm            # dart2wasm
dart run example/png_minifier_example.dart image.png
dart run tool/benchmark.dart -d kodak -p lossless,photo
```

Test fixtures: [PngSuite](http://www.schaik.com/pngsuite/) (every PNG
variant and corrupt files), crops of the
[Kodak suite](https://r0k.us/graphics/kodak/) and
[Kenney](https://kenney.nl) CC0 tilemaps — see
[test/fixtures/README.md](test/fixtures/README.md).

# Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

[Apache License - Version 2.0][apache_license]

[apache_license]: https://www.apache.org/licenses/LICENSE-2.0.txt
