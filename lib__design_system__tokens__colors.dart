import 'package:flutter/material.dart';

/// Raw palette. Screens never use these directly; they read [SdColors]
/// and the [ColorScheme] from the theme, so branding can change per institution.
abstract final class SdPalette {
  /// Default brand: register-ink blue. Replaced by the institution's colour.
  static const ink = Color(0xFF1D4E89);

  static const text = Color(0xFF1B1F24);
  static const textMuted = Color(0xFF5B6470);
  static const border = Color(0xFFDDE1E6);
  static const surface = Color(0xFFF6F7F9);
  static const card = Color(0xFFFFFFFF);

  static const darkText = Color(0xFFE8EAED);
  static const darkTextMuted = Color(0xFF9AA3AE);
  static const darkBorder = Color(0xFF2E343C);
  static const darkSurface = Color(0xFF15181C);
  static const darkCard = Color(0xFF1E2228);

  /// Brand colours an institution can choose. All keep white text readable.
  static const brandChoices = [
    Color(0xFF1D4E89), // register ink
    Color(0xFF283593), // indigo
    Color(0xFF00695C), // teal
    Color(0xFF2E7D32), // green
    Color(0xFF8E2442), // maroon
    Color(0xFF5E35B1), // violet
    Color(0xFF6D4C41), // brown
    Color(0xFF37474F), // slate
  ];
}

/// Semantic colours that are not part of Material's [ColorScheme].
/// Attendance colours are fixed so they mean the same thing everywhere.
@immutable
class SdColors extends ThemeExtension<SdColors> {
  const SdColors({
    required this.border,
    required this.textMuted,
    required this.subtleFill,
    required this.present,
    required this.absent,
    required this.leave,
    required this.info,
  });

  final Color border;
  final Color textMuted;
  final Color subtleFill;
  final Color present;
  final Color absent;
  final Color leave;
  final Color info;

  static const light = SdColors(
    border: SdPalette.border,
    textMuted: SdPalette.textMuted,
    subtleFill: Color(0xFFEEF1F4),
    present: Color(0xFF2E7D32),
    absent: Color(0xFFC62828),
    leave: Color(0xFFB26A00),
    info: Color(0xFF1565C0),
  );

  static const dark = SdColors(
    border: SdPalette.darkBorder,
    textMuted: SdPalette.darkTextMuted,
    subtleFill: Color(0xFF252A31),
    present: Color(0xFF66BB6A),
    absent: Color(0xFFEF5350),
    leave: Color(0xFFFFB74D),
    info: Color(0xFF64B5F6),
  );

  static SdColors of(BuildContext context) =>
      Theme.of(context).extension<SdColors>() ?? light;

  @override
  SdColors copyWith({
    Color? border,
    Color? textMuted,
    Color? subtleFill,
    Color? present,
    Color? absent,
    Color? leave,
    Color? info,
  }) {
    return SdColors(
      border: border ?? this.border,
      textMuted: textMuted ?? this.textMuted,
      subtleFill: subtleFill ?? this.subtleFill,
      present: present ?? this.present,
      absent: absent ?? this.absent,
      leave: leave ?? this.leave,
      info: info ?? this.info,
    );
  }

  @override
  SdColors lerp(ThemeExtension<SdColors>? other, double t) {
    if (other is! SdColors) return this;
    return SdColors(
      border: Color.lerp(border, other.border, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      subtleFill: Color.lerp(subtleFill, other.subtleFill, t)!,
      present: Color.lerp(present, other.present, t)!,
      absent: Color.lerp(absent, other.absent, t)!,
      leave: Color.lerp(leave, other.leave, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}
