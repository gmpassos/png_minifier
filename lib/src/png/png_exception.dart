/// Thrown when bytes are not a valid PNG, or use a feature this package does
/// not read (an unknown critical chunk, for instance).
class PngFormatException implements Exception {
  /// What is wrong with the input.
  final String message;

  /// Creates an exception with [message].
  const PngFormatException(this.message);

  @override
  String toString() => 'PngFormatException: $message';
}
