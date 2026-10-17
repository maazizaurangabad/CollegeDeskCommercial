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
