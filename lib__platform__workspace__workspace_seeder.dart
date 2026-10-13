import '../../core/database/app_database.dart';
import '../../core/session/app_session.dart';
import '../../modules/students/data/demo_students.dart';
import '../academic/academic_repository.dart';
import '../academic/structure_templates.dart';
import '../data/organization_repository.dart';
import '../demo/demo_data.dart';
import '../modules/module_registry.dart';
import 'institution_creator.dart';

/// Fills a demo workspace with the fictional institution and students.
/// Safe to call every start: it only adds what is missing.
class WorkspaceSeeder {
  WorkspaceSeeder(this.db, this.session);

  final AppDatabase db;
  final AppSession session;

  Future<void> seedDemoIfEmpty(ModuleRegistry registry, {int studentCount = 500}) async {
    final organizations = OrganizationRepository(db, session);
    final year = DemoData.academicYear;
    if (await organizations.loadActive() == null) {
      await InstitutionCreator(db, session).create(
        profile: DemoData.organization,
        yearLabel: year.label,
        yearStart: year.start,
        yearEnd: year.end,
        template: StructureTemplate.juniorCollege,
        registry: registry,
      );
    }

    // Demo workspaces created by build 1b have no academic structure yet.
    final academic = AcademicRepository(db, session);
    if ((await academic.listYears()).isEmpty) {
      await db.transaction(() => InstitutionCreator.applyStructure(
            academic,
            yearLabel: year.label,
            yearStart: year.start,
            yearEnd: year.end,
            template: StructureTemplate.juniorCollege,
          ));
    }

    await _seedStudentsIfNone(academic, studentCount);
  }

  Future<void> _seedStudentsIfNone(AcademicRepository academic, int count) async {
    final existing = await (db.select(db.students)
          ..where((t) => t.organizationId.equals(session.organizationId))
          ..limit(1))
        .get();
    if (existing.isNotEmpty) return;
    final snapshot = await academic.loadSnapshot();
    final year = snapshot.activeYear;
    if (year == null) return;
    await DemoStudents.seed(
      db,
      session,
      academicYearId: year.id,
      divisionIds: snapshot.divisions.map((d) => d.id).toList(),
      count: count,
    );
  }
}
