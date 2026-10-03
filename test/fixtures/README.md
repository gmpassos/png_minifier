# Test fixtures

| Directory | Source | Licence |
|---|---|---|
| `pngsuite/` | [PngSuite](http://www.schaik.com/pngsuite/) 2017-07-19 by Willem van Schaik: every colour type, bit depth, interlacing, transparency and chunk case, plus corrupt files (`x*.png`). | "Permission to use, copy, modify and distribute these images for any purpose and without fee is hereby granted." (`pngsuite/PngSuite.LICENSE`) |
| `kodak/` | 192×128 crops of `kodim03`, `kodim15` and `kodim23` from the [Kodak Lossless True Color Image Suite](https://r0k.us/graphics/kodak/), stored as plain RGB PNGs. Rebuilt with `dart run tool/benchmark.dart --make-fixtures`. | Released by the Eastman Kodak Company for unrestricted usage. |
| `kenney/` | Tilemaps from the [Kenney](https://kenney.nl) packs *Tiny Town* and *Pixel Platformer*, and the *UI Pack* sample sheet. | CC0 1.0 (public domain); `kenney/License.txt`. |

The full Kodak suite and Kenney packs are not committed: `tool/benchmark.dart`
downloads them into `.benchmark/` (git-ignored).
