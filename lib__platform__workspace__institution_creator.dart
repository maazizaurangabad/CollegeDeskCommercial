import '../../core/database/app_database.dart';
import '../../core/session/app_session.dart';
import '../academic/academic_repository.dart';
import '../academic/structure_templates.dart';
import '../data/module_settings_repository.dart';
import '../data/organization_repository.dart';
import '../modules/module_registry.dart';
import '../organization/organization_profile.dart';

/// Writes a new institution: its record, first academic year,
/// classes and divisions from a template, and default modules.
/// One transaction, so a failure leaves nothing half-created.
class InstitutionCreator {
  InstitutionCreator(this.db, this.session);

  final AppDatabase db;
  final AppSession session;

  Future<void> create({
    required OrganizationProfile profile,
    required String yearLabel,
    required DateTime yearStart,
    required DateTime yearEnd,
    required StructureTemplate template,
    required ModuleRegistry registry,
  }) {
    final structure = structureFor(template);
    return db.transaction(() async {
      await OrganizationRepository(db, session).create(profile.copyWith(
        activeAcademicYear: yearLabel,
        programLabel: structure.programLabel,
        divisionLabel: structure.divisionLabel,
      ));
      final academic = AcademicRepository(db, session);
      await applyStructure(academic, yearLabel: yearLabel, yearStart: yearStart, yearEnd: yearEnd, template: template);
      final modules = ModuleSettingsRepository(db, session);
      for (final m in registry.installed.where((m) => !m.isCore)) {
        await modules.setEnabled(m.id, m.defaultEnabled);
      }
    });
  }

  /// Adds the first (active) year and the template's classes and divisions.
  static Future<void> applyStructure(
    AcademicRepository academic, {
    required String yearLabel,
    required DateTime yearStart,
    required DateTime yearEnd,
    required StructureTemplate template,
  }) async {
    final structure = structureFor(template);
    final yearId = await academic.addYear(label: yearLabel, startDate: yearStart, endDate: yearEnd, makeActive: true);
    final idsByName = <String, String>{};
    for (final p in structure.programs) {
      final id = await academic.addProgram(name: p.name, stream: p.stream);
      idsByName[p.name] = id;
      for (final d in p.divisions) {
        await academic.addDivision(programId: id, academicYearId: yearId, name: d);
      }
    }
    for (final p in structure.programs) {
      final next = p.next == null ? null : idsByName[p.next];
      if (next != null) await academic.setNextProgram(idsByName[p.name]!, next);
    }
  }
}
