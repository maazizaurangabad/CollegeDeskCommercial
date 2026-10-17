import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/startup/startup_state.dart';
import '../../core/database/app_database.dart';
import '../../core/session/app_session.dart';
import 'app_settings_repository.dart';
import 'module_settings_repository.dart';
import 'organization_repository.dart';
import '../staff/staff_models.dart';

/// Filled in by main() (or a test) once the database is open.
final startupStateProvider = Provider<StartupState>(
  (ref) => throw UnimplementedError('startupStateProvider must be overridden at start-up'),
);

final appDatabaseProvider = Provider<AppDatabase>((ref) => ref.watch(startupStateProvider).database);

/// Who is using the app right now. The app lock owns the notifier
/// (it changes on every login); the administrator by default.
final currentUserNotifierProvider = Provider<ValueNotifier<CurrentUser>>((ref) {
  final notifier = ValueNotifier<CurrentUser>(CurrentUser.owner);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// The current user; screens rebuild when someone else logs in.
final currentUserProvider = Provider<CurrentUser>((ref) {
  final notifier = ref.watch(currentUserNotifierProvider);
  void changed() => ref.invalidateSelf();
  notifier.addListener(changed);
  ref.onDispose(() => notifier.removeListener(changed));
  return notifier.value;
});

/// Every change is recorded under the person logged in at that moment.
final sessionProvider = Provider<AppSession>((ref) {
  final s = ref.watch(startupStateProvider).session;
  final user = ref.watch(currentUserNotifierProvider);
  return AppSession(
    organizationId: s.organizationId,
    deviceId: s.deviceId,
    userId: s.userId,
    activeUserId: () => user.value.isOwner ? null : user.value.id,
  );
});

final organizationRepositoryProvider = Provider<OrganizationRepository>(
  (ref) => OrganizationRepository(ref.watch(appDatabaseProvider), ref.watch(sessionProvider)),
);

final moduleSettingsRepositoryProvider = Provider<ModuleSettingsRepository>(
  (ref) => ModuleSettingsRepository(ref.watch(appDatabaseProvider), ref.watch(sessionProvider)),
);

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => AppSettingsRepository(ref.watch(appDatabaseProvider), ref.watch(sessionProvider)),
);
