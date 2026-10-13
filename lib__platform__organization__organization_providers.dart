import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/startup/app_bootstrap.dart';
import '../data/app_settings_repository.dart';
import '../data/data_providers.dart';
import 'organization_profile.dart';

/// Whether the open institution is the demo (sample data only).
final isDemoModeProvider = Provider<bool>((ref) => ref.watch(startupStateProvider).isDemo);

/// The institution currently open on this device.
final activeOrganizationProvider = StateProvider<OrganizationProfile>(
  (ref) => ref.watch(startupStateProvider).organization,
);

/// Light, dark or follow the device. Saved per institution.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(
    ref.watch(startupStateProvider).themeMode,
    ref.watch(appSettingsRepositoryProvider),
  ),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(super.initial, this._settings);

  final AppSettingsRepository _settings;

  Future<void> change(ThemeMode mode) async {
    final previous = state;
    state = mode;
    try {
      await _settings.setValue(AppBootstrap.themeModeKey, mode.name);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

/// Permission check used by every service and screen.
/// Single administrator until Phase 3; roles plug in here without changing callers.
final permissionCheckerProvider = Provider<bool Function(String permission)>((ref) => (_) => true);
