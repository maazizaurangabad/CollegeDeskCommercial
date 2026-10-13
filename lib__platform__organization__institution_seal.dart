import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../design_system/tokens/spacing.dart';

/// The institution's mark: its logo if it has one, otherwise its
/// initials drawn like a register seal in its brand colour.
class InstitutionSeal extends StatelessWidget {
  const InstitutionSeal({
    super.key,
    required this.initials,
    required this.color,
    this.logoFile,
    this.size = 36,
  });

  final String initials;
  final Color color;
  final File? logoFile;
  final double size;

  /// Resolves the stored logo name inside the institution's folder.
  static File? logoIn(Directory? mediaDir, String? logoFileName) {
    if (mediaDir == null || logoFileName == null) return null;
    final file = File(p.join(mediaDir.path, logoFileName));
    return file.existsSync() ? file : null;
  }

  @override
  Widget build(BuildContext context) {
    final logo = logoFile;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: logo == null ? color.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(SdRadius.sm),
        border: Border.all(color: color, width: 1.5),
      ),
      child: logo != null
          ? Image.file(logo, fit: BoxFit.contain, width: size, height: size)
          : Text(
              initials,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.36,
                letterSpacing: 0.8,
              ),
            ),
    );
  }
}
