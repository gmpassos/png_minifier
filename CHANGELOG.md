## 1.0.0

- First release: minify PNG images in pure Dart.
  - Many strategies compete per image; the smallest result meeting the
    quality target wins, with the input returned when nothing is smaller.
  - Lossless strategies: transparent-pixel cleanup, colour-type and
    bit-depth reduction (RGB, greyscale 1–16 bits, grey+alpha, tRNS colour
    keys), indexed palettes at 1/2/4/8 bits, three palette orders, seven PNG
    filter strategies, deflate-level search.
  - Lossy strategies, each checked against the quality before it may win:
    frequency palette (pixel art), median cut, k-means, bounded
    Floyd–Steinberg dithering, posterize, alpha snapping.
  - Quality: `PngQuality.lossless()` (default), `.maxError(n)`,
    `.psnr(dB)`, `.bounded(...)` or a TinyPNG-like `.level(0–100)`, measured
    on premultiplied colour.
  - Effort `fast | balanced | max` and presets `lossless`, `losslessMax`,
    `fast`, `web`, `pixelArt`, `photo`, `smallest`.
  - Full PNG decoder (all colour types and bit depths, Adam7, tRNS, CRC
    checks) and encoder; APNG input is returned unchanged.
  - Metadata: strip, keep colour chunks (default) or keep all valid chunks.
  - Deterministic output, identical on the VM, dart2js and dart2wasm.
  - `png_minifier` command line: files and directories, `--preset`,
    `--quality`, `--effort`, `--strategies`, `--in-place`, `--dry-run`,
    `--json`.
- Tests on PngSuite, Kodak crops and Kenney tilemaps; golden hashes checked
  on the VM, Chrome (dart2js) and Chrome (dart2wasm); `tool/benchmark.dart`.
