import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/data_providers.dart';
import 'staff_models.dart';
import 'staff_repository.dart';

final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => StaffRepository(ref.watch(appDatabaseProvider), ref.watch(sessionProvider)),
);

/// Bumped after any staff or role change.
final staffRevisionProvider = StateProvider<int>((ref) => 0);

final staffListProvider = FutureProvider<List<StaffMember>>((ref) {
  ref.watch(staffRevisionProvider);
  return ref.watch(staffRepositoryProvider).list();
});

final staffRolesProvider = FutureProvider<List<StaffRole>>((ref) {
  ref.watch(staffRevisionProvider);
  return ref.watch(staffRepositoryProvider).roles();
});

/// Staff names by user id (including switched-off and removed staff), for
/// "Issued by" and the activity log.
final staffNamesProvider = FutureProvider<Map<String, String>>((ref) {
  ref.watch(staffRevisionProvider);
  return ref.watch(staffRepositoryProvider).names();
});

/// The name to show for whoever made a change; null when not known.
String? userDisplayName(Map<String, String> names, String? userId, {String adminName = 'Admin'}) {
  if (userId == null || userId.isEmpty) return null;
  if (userId == localAdminUserId) return adminName;
  return names[userId];
}

/// Classes (divisions) the person logged in may work with; null means all.
/// A Teacher (or anyone given classes in their staff record) sees only
/// their own classes' students, attendance and marks.
final allowedDivisionsProvider = Provider<Set<String>?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user.isOwner) return null;
  if (user.roleKey == StaffRoles.teacherKey || user.divisionIds.isNotEmpty) return user.divisionIds.toSet();
  return null;
});
