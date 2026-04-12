extension StringCapitalize on String {
  /// Capitalizes only the very first character, leaving the rest unchanged.
  /// "vitkindad gås" → "Vitkindad gås"
  String get sentenceCase {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
