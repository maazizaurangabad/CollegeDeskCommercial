import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/data_providers.dart';
import '../organization/organization_providers.dart';
import 'academic_models.dart';
import 'academic_repository.dart';

final academicRepositoryProvider = Provider<AcademicRepository>(
  (ref) => AcademicRepository(ref.watch(appDatabaseProvider), ref.watch(sessionProvider)),
);

/// Years, classes and divisions as the screens see them.
/// Every action saves first, then reloads, so the screen always
/// shows what is really in the database.
final academicControllerProvider = StateNotifierProvider<AcademicController, AcademicSnapshot>(
  (ref) => AcademicController(ref, ref.watch(startupStateProvider).academic, ref.watch(academicRepositoryProvider)),
);

class AcademicController extends StateNotifier<AcademicSnapshot> {
  AcademicController(this._ref, super.initial, this._repository);

  final Ref _ref;
  final AcademicRepository _repository;

  Future<void> _run(Future<void> Function() action) async {
    await action();
    state = await _repository.loadSnapshot();
    final active = state.activeYear;
    final org = _ref.read(activeOrganizationProvider);
    if (active != null && org.activeAcademicYear != active.label) {
      _ref.read(activeOrganizationProvider.notifier).state = org.copyWith(activeAcademicYear: active.label);
    }
  }

  /// Re-reads everything, e.g. after an import created classes.
  Future<void> reload() => _run(() async {});

  Future<void> addYear(String label, DateTime start, DateTime end) =>
      _run(() => _repository.addYear(label: label, startDate: start, endDate: end, makeActive: state.years.isEmpty));

  Future<void> setActiveYear(String id) => _run(() => _repository.setActiveYear(id));

  Future<void> closeYear(String id) => _run(() => _repository.closeYear(id));

  Future<void> addProgram(String name, {String? stream}) => _run(() async {
        await _repository.addProgram(name: name, stream: stream);
      });

  Future<void> renameProgram(String id, String name) => _run(() => _repository.renameProgram(id, name));

  Future<void> moveProgram(String id, {required bool up}) => _run(() => _repository.moveProgram(id, up: up));

  Future<void> deleteProgram(String id) => _run(() => _repository.deleteProgram(id));

  Future<void> addDivision(String programId, String name) => _run(() async {
        final year = state.activeYear;
        if (year == null) throw const AcademicValidationException(AcademicIssue.notFound);
        await _repository.addDivision(programId: programId, academicYearId: year.id, name: name);
      });

  Future<void> renameDivision(String id, String name) => _run(() => _repository.renameDivision(id, name));

  Future<void> deleteDivision(String id) => _run(() => _repository.deleteDivision(id));
}
