import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Builds the app theme from the institution's brand colour.
/// Every screen gets its look from here; no screen sets its own colours.
ThemeData buildSdTheme({required Color brand, required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;
  final sd = isDark ? SdColors.dark : SdColors.light;
  final seeded = ColorScheme.fromSeed(seedColor: brand, brightness: brightness);
  final scheme = seeded.copyWith(
    primary: isDark ? seeded.primary : brand,
    surface: isDark ? SdPalette.darkCard : SdPalette.card,
    onSurface: isDark ? SdPalette.darkText : SdPalette.text,
    outline: sd.border,
    outlineVariant: sd.border,
  );
  final background = isDark ? SdPalette.darkSurface : SdPalette.surface;
  final text = sdTextTheme(text: scheme.onSurface, muted: sd.textMuted);
  final radiusSm = BorderRadius.circular(SdRadius.sm);
  const buttonSize = Size(0, 44);

  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(borderRadius: radiusSm, borderSide: BorderSide(color: color, width: width));

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    textTheme: text,
    extensions: [sd],
    dividerTheme: DividerThemeData(color: sd.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleMedium,
      shape: Border(bottom: BorderSide(color: sd.border)),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SdRadius.sm),
        side: BorderSide(color: sd.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      selectedLabelTextStyle: text.labelLarge?.copyWith(color: scheme.primary),
      unselectedLabelTextStyle: text.labelLarge?.copyWith(color: sd.textMuted),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: SdSpace.md, vertical: SdSpace.md),
      border: inputBorder(sd.border),
      enabledBorder: inputBorder(sd.border),
      focusedBorder: inputBorder(scheme.primary, 1.5),
      errorBorder: inputBorder(sd.absent),
      hintStyle: text.bodyMedium?.copyWith(color: sd.textMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: buttonSize, shape: RoundedRectangleBorder(borderRadius: radiusSm)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonSize,
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
        side: BorderSide(color: sd.border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: buttonSize, shape: RoundedRectangleBorder(borderRadius: radiusSm)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SdRadius.md)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SdRadius.md)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radiusSm),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: SdSpace.lg),
      iconColor: sd.textMuted,
      subtitleTextStyle: text.bodySmall,
    ),
  );
}
