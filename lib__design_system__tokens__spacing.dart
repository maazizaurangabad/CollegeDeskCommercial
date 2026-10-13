/// 4-point spacing grid. Use these instead of raw numbers.
abstract final class SdSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Corner radii: inputs and cards 8, sheets 12, chips fully round.
abstract final class SdRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double pill = 999;
}

/// Width breakpoints for responsive layouts.
abstract final class SdBreakpoints {
  /// Below this: phone layout with bottom navigation.
  static const double compact = 600;

  /// At or above this: desktop layout with a full sidebar.
  static const double expanded = 1024;

  /// Content never grows wider than this, so lines stay readable.
  static const double maxContentWidth = 1120;
}
