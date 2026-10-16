import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/core/validation/aadhaar.dart';
import 'package:shiksha_desk/modules/search/application/student_search.dart';
import 'package:shiksha_desk/modules/students/data/field_definition_repository.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

StudentListItem _s(String id, String name, {String? div, int? roll}) => StudentListItem(
      id: id,
      displayCode: id,
      fullName: name,
      status: StudentStatus.active,
      divisionId: div,
      rollNumber: roll,
    );

void main() {
  test('a number alone is a roll number', () {
    expect(rollQuery('11'), 11);
    expect(rollQuery(' 7 '), 7);
    expect(rollQuery('a1'), isNull);
    expect(rollQuery('12345'), isNull); // longer numbers are G.R., mobiles, PEN...
  });

  test('roll matches first, each student once, only the chosen classes', () {
    final all = [
      _s('1', 'Zoya', div: 'A', roll: 3),
      _s('2', 'Ayaan', div: 'B', roll: 3),
      _s('3', 'Riya', div: 'A', roll: 1),
    ];
    // "3" is roll 3 for Zoya and Ayaan, and also appears in Riya's text.
    final found = mergeSearch(query: '3', byText: [all[2], all[0]], all: all);
    expect(found.map((s) => s.fullName), ['Ayaan', 'Zoya', 'Riya']);
    expect(mergeSearch(query: '3', byText: const [], all: all, divisionIds: {'A'}).map((s) => s.fullName), ['Zoya']);
    // No text, a class chosen: the whole class by roll.
    expect(mergeSearch(query: '', byText: const [], all: all, divisionIds: {'A'}).map((s) => s.fullName), ['Riya', 'Zoya']);
  });

  group('with a database', () {
    late AppDatabase db;
    late StudentRepository students;
    late FieldDefinitionRepository fields;
    late AppSettingsRepository settings;
    late String divA;
    final aadhaar = '23456789012${Aadhaar.checkDigit('23456789012')}';

    setUp(() async {
      db = newMemoryDatabase();
      await InstitutionCreator(db, testSession).create(
        profile: DemoData.organization,
        yearLabel: '2026-27',
        yearStart: DateTime(2026, 6, 1),
        yearEnd: DateTime(2027, 4, 30),
        template: StructureTemplate.juniorCollege,
        registry: buildModuleRegistry(),
      );
      divA = (await AcademicRepository(db, testSession).loadSnapshot()).divisions.first.id;
      students = StudentRepository(db, testSession, testCipher);
      fields = FieldDefinitionRepository(db, testSession);
      settings = AppSettingsRepository(db, testSession);
    });
    tearDown(() => db.close());

    test('the FYJC fields are added once', () async {
      expect(await fields.addSet(JuniorCollegeFields.fields), JuniorCollegeFields.fields.length);
      expect(await fields.addSet(JuniorCollegeFields.fields), 0);
      final labels = (await fields.listForStudents()).map((f) => f.label);
      expect(labels, containsAll(['Name as per FYJC', 'FYJC Application ID', '10th percentage', 'DOB as per APAAR']));
      expect(labels.any((l) => l.toLowerCase().contains('password')), isFalse);
    });

    test('own fields and roll numbers are searchable; Aadhaar is not', () async {
      await fields.addSet(JuniorCollegeFields.fields);
      final defs = await fields.listForStudents();
      final fyjcId = defs.firstWhere((f) => f.label == 'FYJC Application ID');
      final year = (await AcademicRepository(db, testSession).loadSnapshot()).activeYear!.id;
      final id = await students.create(
        StudentDraft(
          firstName: 'Fatima',
          lastName: 'Shaikh',
          divisionId: divA,
          rollNumber: 11,
          extra: {fyjcId.key: 'K0084131678'},
          identifiers: {IdentifierType.aadhaar: aadhaar},
        ),
        extraFields: defs,
      );

      Future<List<String>> find(String q) async =>
          (await searchStudents(students, query: q, academicYearId: year)).map((s) => s.id).toList();

      expect(await find('K0084131678'), [id]);
      expect(await find('k00841'), [id]); // part of it, any case
      expect(await find('11'), [id]); // roll number
      expect(await find(aadhaar), isEmpty);
      expect(await find(aadhaar.substring(8)), isEmpty);
    });

    test('students saved before the update become searchable by own fields once', () async {
      await fields.addSet(JuniorCollegeFields.fields);
      final defs = await fields.listForStudents();
      final fyjcId = defs.firstWhere((f) => f.label == 'FYJC Application ID');
      await students.create(StudentDraft(firstName: 'Imran', extra: {fyjcId.key: 'K0099'}), extraFields: defs);
      // As if saved by an older version: no own-field values in the search text.
      await db.update(db.students).write(const StudentsCompanion(searchText: Value('imran')));
      expect(await students.list(query: 'K0099'), isEmpty);

      expect(await students.ensureSearchIndex(settings), isTrue);
      expect((await students.list(query: 'K0099')).single.fullName, 'Imran');
      expect(await students.ensureSearchIndex(settings), isFalse); // only once
    });
  });
}
