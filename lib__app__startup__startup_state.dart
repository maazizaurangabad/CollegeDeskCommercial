import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/security/field_cipher.dart';
import '../../core/session/app_session.dart';
import '../../platform/academic/academic_models.dart';
import '../../platform/organization/organization_profile.dart';

/// Everything loaded before the first screen of an institution appears.
class StartupState {
  const StartupState({
    required this.database,
    required this.session,
    required this.organization,
    required this.academic,
    required this.enabledModules,
    required this.themeMode,
    required this.encrypted,
    required this.isDemo,
    required this.fieldCipher,
    this.mediaDir,
  });

  final AppDatabase database;
  final AppSession session;
  final OrganizationProfile organization;
  final AcademicSnapshot academic;
  final Set<String> enabledModules;
  final ThemeMode themeMode;
  final bool encrypted;
  final bool isDemo;

  /// Second encryption layer for Aadhaar numbers.
  final FieldCipher fieldCipher;

  /// This institution's own folder for files such as the logo. Null in tests.
  final Directory? mediaDir;
}
