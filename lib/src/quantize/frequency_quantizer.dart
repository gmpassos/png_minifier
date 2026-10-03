import '../image/color_histogram.dart';
import 'palette_mapper.dart';

/// The palette for pixel art: the most used colours kept exactly, each rarer
/// colour mapped to a kept one within [maxError].
///
/// Colours are taken most used first; one already within [maxError] of a
/// kept colour is covered by it, any other becomes a palette entry. Spare
/// slots then take the most used colours not yet exact. Returns null when
/// more than [maxColors] entries would be needed.
PaletteIndex? frequencyPalette(
  ColorHistogram histogram, {
  required int maxColors,
  required int maxError,
}) {
  final palette = PaletteIndex();
  if (!coverRemaining(histogram, palette, maxColors, maxError)) return null;
  final exact = palette.entries.toSet();
  for (final c in histogram.colors) {
    if (palette.length >= maxColors) break;
    if (exact.add(c)) palette.add(c);
  }
  return palette;
}
