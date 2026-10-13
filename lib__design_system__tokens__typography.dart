import 'package:flutter/material.dart';

/// Type scale 12 / 14 / 16 / 20 / 24 / 32. System fonts in version 1;
/// bundled Noto fonts arrive with additional languages.
TextTheme sdTextTheme({required Color text, required Color muted}) {
  const tabular = [FontFeature.tabularFigures()];
  return TextTheme(
    displaySmall: TextStyle(fontSize: 32, height: 1.2, fontWeight: FontWeight.w600, color: text, fontFeatures: tabular),
    headlineSmall: TextStyle(fontSize: 24, height: 1.25, fontWeight: FontWeight.w600, color: text),
    titleLarge: TextStyle(fontSize: 20, height: 1.3, fontWeight: FontWeight.w600, color: text),
    titleMedium: TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w600, color: text),
    titleSmall: TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600, color: text),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: text),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: text),
    bodySmall: TextStyle(fontSize: 12, height: 1.4, color: muted),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: text),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: muted),
  );
}
