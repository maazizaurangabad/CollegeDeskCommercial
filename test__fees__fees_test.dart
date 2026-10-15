import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/l10n/gen/app_localizations_en.dart';
import 'package:shiksha_desk/modules/fees/application/fee_reports.dart';
import 'package:shiksha_desk/modules/fees/data/fee_repository.dart';
import 'package:shiksha_desk/modules/fees/domain/fee_models.dart';
import 'package:shiksha_desk/modules/students/data/student_repository.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/platform/academic/academic_models.dart';
import 'package:shiksha_desk/platform/academic/academic_repository.dart';
import 'package:shiksha_desk/platform/academic/structure_templates.dart';
import 'package:shiksha_desk/platform/data/app_settings_repository.dart';
import 'package:shiksha_desk/platform/demo/demo_data.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';
import 'package:shiksha_desk/platform/workspace/institution_creator.dart';

import '../test_support.dart';

void main() {
  test('rupees are grouped and written the Indian way', () {
    expect(Rupees.format(950), '950');
    expect(Rupees.format(12500), '12,500');
    expect(Rupees.format(125000), '1,25,000');
    expect(Rupees.format(12345678), '1,23,45,678');
    expect(Rupees.words(0), 'Rupees Zero Only');
    expect(Rupees.words(5250), 'Rupees Five Thousand Two Hundred Fifty Only');
    expect(Rupees.words(125000), 'Rupees One Lakh Twenty Five Thousand Only');
    expect(Rupees.words(10000101), 'Rupees One Crore One Hundred One Only');
  });

  group('fees', () {
    final today = DateTime(2026, 10, 14, 11);
    late AppDatabase db;
    late FeeRepository fees;
    late AcademicSnapshot academic;
    late String yearId;
    late String programId;
    late String openStudent;
    late String scStudent;
    late Map<String, String> headId;

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
      academic = await AcademicRepository(db, testSession).loadSnapshot();
      yearId = academic.activeYear!.id;
      final division = academic.divisions.first;
      programId = division.programId;
      final students = StudentRepository(db, testSession, testCipher);
      openStudent = await students.create(StudentDraft(
        firstName: 'Ayaan',
        lastName: 'Shaikh',
        category: 'Open',
        divisionId: division.id,
        rollNumber: 1,
        admissionDate: DateTime(2026, 6, 15),
        identifiers: {IdentifierType.grNumber: '4512'},
      ));
      scStudent = await students.create(StudentDraft(
        firstName: 'Rahul',
        lastName: 'Kamble',
        category: 'SC',
        divisionId: division.id,
        rollNumber: 2,
        admissionDate: DateTime(2026, 6, 15),
      ));
      fees = FeeRepository(db, testSession, AppSettingsRepository(db, testSession), students, clock: () => today);
      headId = {for (final h in await fees.heads()) h.name: h.id};
    });
    tearDown(() => db.close());

    Future<void> setFees() async {
      await fees.saveStructure(
        academicYearId: yearId,
        programId: programId,
        amounts: {headId['Admission fee']!: 500, headId['Tuition fee']!: 4000, headId['Examination fee']!: 300},
      );
      // SC students: no tuition (freeship).
      await fees.saveStructure(
        academicYearId: yearId,
        programId: programId,
        category: 'sc',
        amounts: {headId['Admission fee']!: 500, headId['Examination fee']!: 300},
      );
    }

    test('standard heads are added once and can be renamed, switched off, reordered and deleted when unused', () async {
      expect(headId.length, FeeRepository.defaultHeads.length);
      expect((await fees.heads()).length, FeeRepository.defaultHeads.length);
      await fees.updateHead(headId['Other fee']!, name: 'Development fee');
      await expectLater(() => fees.updateHead(headId['Term fee']!, name: 'tuition FEE'),
          throwsA(isA<FeeException>().having((e) => e.issue, 'issue', FeeIssue.duplicateName)));
      await fees.moveHead(headId['Tuition fee']!, -1);
      expect((await fees.heads()).first.name, 'Tuition fee');
      await fees.updateHead(headId['Laboratory fee']!, isActive: false);
      expect((await fees.heads()).firstWhere((h) => h.id == headId['Laboratory fee']).isActive, isFalse);
      await fees.deleteHead(headId['Laboratory fee']!);
      expect((await fees.heads()).any((h) => h.id == headId['Laboratory fee']), isFalse);

      await setFees();
      await expectLater(() => fees.deleteHead(headId['Tuition fee']!),
          throwsA(isA<FeeException>().having((e) => e.issue, 'issue', FeeIssue.headInUse)));
    });

    test('a category structure replaces the class one only for that category', () async {
      await setFees();
      final open = await fees.account(openStudent, yearId);
      expect(open.due, 4800);
      expect(open.structureCategory, isNull);
      expect(open.grNumber, '4512');
      expect(open.classLabel, isNotEmpty);

      final sc = await fees.account(scStudent, yearId);
      expect(sc.due, 800);
      expect(sc.structureCategory, 'sc');

      // Saving again replaces, it does not add a second structure.
      await fees.saveStructure(
        academicYearId: yearId,
        programId: programId,
        category: 'SC',
        amounts: {headId['Admission fee']!: 0, headId['Examination fee']!: 300},
      );
      expect((await fees.account(scStudent, yearId)).due, 300);
      expect((await fees.structures(yearId)).length, 2);
    });

    test('concessions and extra charges change what is due', () async {
      await setFees();
      await fees.addAdjustment(
        studentId: openStudent,
        academicYearId: yearId,
        headId: headId['Tuition fee']!,
        amount: -1000,
        reason: 'Staff ward',
      );
      await fees.addAdjustment(
        studentId: openStudent,
        academicYearId: yearId,
        headId: headId['Library fee']!,
        amount: 200,
        reason: 'Lost book',
      );
      final a = await fees.account(openStudent, yearId);
      expect(a.due, 4000);
      expect(a.lines.firstWhere((l) => l.headId == headId['Library fee']).due, 200);
      await expectLater(
        () => fees.addAdjustment(studentId: openStudent, academicYearId: yearId, headId: headId['Tuition fee']!, amount: -5, reason: ' '),
        throwsA(isA<FeeException>().having((e) => e.issue, 'issue', FeeIssue.noReason)),
      );
      await fees.deleteAdjustment(a.adjustments.first.id);
      expect((await fees.account(openStudent, yearId)).due, 5000);
    });

    test('payments make numbered receipts, fill heads in order, and cancelled numbers are never reused', () async {
      await setFees();
      var a = await fees.account(openStudent, yearId);
      final split = a.allocate(2000);
      expect(split.byHead, {headId['Admission fee']!: 500, headId['Tuition fee']!: 1500});
      expect(split.rest, 0);
      expect(a.allocate(9999).rest, 9999 - 4800);

      final r1 = await fees.takePayment(
        studentId: openStudent,
        academicYearId: yearId,
        byHead: split.byHead,
        mode: PaymentMode.cash,
        receivedOn: today,
      );
      final first = (await fees.receipt(r1))!;
      expect(first.serialLabel, 'REC/2026-27/0001');
      expect(first.total, 2000);
      expect(first.balanceAfter, 2800);
      expect(first.grNumber, '4512');

      await fees.setReceiptPrefix('FEE');
      final r2 = await fees.takePayment(
        studentId: openStudent,
        academicYearId: yearId,
        byHead: {headId['Tuition fee']!: 2500},
        mode: PaymentMode.upi,
        reference: 'UPI123',
        receivedOn: today,
      );
      expect((await fees.receipt(r2))!.serialLabel, 'FEE/2026-27/0002');

      a = await fees.account(openStudent, yearId);
      expect(a.paid, 4500);
      expect(a.balance, 300);

      await fees.cancelReceipt(r2, 'Wrong student');
      a = await fees.account(openStudent, yearId);
      expect(a.paid, 2000);
      expect(a.receipts.firstWhere((r) => r.id == r2).isCancelled, isTrue);

      final r3 = await fees.takePayment(
        studentId: scStudent,
        academicYearId: yearId,
        byHead: {headId['Admission fee']!: 500},
        mode: PaymentMode.cash,
        receivedOn: today,
      );
      expect((await fees.receipt(r3))!.serialLabel, 'FEE/2026-27/0003');

      final day = await fees.collectedOn(today);
      expect(day.total, 2500);
      expect(day.count, 2);
      expect(day.byMode[PaymentMode.cash], 2500);
      expect(await fees.receipts(query: 'kamble'), hasLength(1));

      await expectLater(
        () => fees.takePayment(
          studentId: openStudent,
          academicYearId: yearId,
          byHead: {headId['Tuition fee']!: 100},
          mode: PaymentMode.cash,
          receivedOn: today.add(const Duration(days: 2)),
        ),
        throwsA(isA<FeeException>().having((e) => e.issue, 'issue', FeeIssue.futureDate)),
      );
      await expectLater(
        () => fees.takePayment(
          studentId: openStudent,
          academicYearId: yearId,
          byHead: {headId['Tuition fee']!: 0},
          mode: PaymentMode.cash,
          receivedOn: today,
        ),
        throwsA(isA<FeeException>().having((e) => e.issue, 'issue', FeeIssue.noAmount)),
      );

      final audit = await (db.select(db.auditEntries)..where((t) => t.entity.equals('fee_receipts'))).get();
      expect(audit.map((e) => e.action), containsAll(['insert', 'cancel']));
    });

    test('structures can be copied to a new year', () async {
      await setFees();
      final newYear = await AcademicRepository(db, testSession).addYear(
        label: '2027-28',
        startDate: DateTime(2027, 6, 1),
        endDate: DateTime(2028, 4, 30),
      );
      expect(await fees.copyStructures(fromYearId: yearId, toYearId: newYear), 2);
      expect(await fees.copyStructures(fromYearId: yearId, toYearId: newYear), 0);
      expect((await fees.structures(newYear)).length, 2);
    });

    test('installments decide what is overdue; the all-students list matches each account', () async {
      await setFees();
      final general = (await fees.structures(yearId)).firstWhere((s) => s.category == null);
      await fees.saveDueDates(general.id, [
        FeeDueDate(label: 'First', dueDate: DateTime(2026, 7, 31), amount: 3000),
        FeeDueDate(label: 'Second', dueDate: DateTime(2026, 12, 31), amount: 4800),
      ]);
      await fees.takePayment(
        studentId: openStudent,
        academicYearId: yearId,
        byHead: {headId['Admission fee']!: 500, headId['Tuition fee']!: 1500},
        mode: PaymentMode.cash,
        receivedOn: today,
      );
      final a = await fees.account(openStudent, yearId);
      expect(a.balance, 2800);
      expect(a.overdue, 1000); // 3000 due by 31 Jul, 2000 paid
      expect(a.nextDue?.label, 'Second');

      // SC structure has no installments: everything is due now.
      final sc = await fees.account(scStudent, yearId);
      expect(sc.overdue, 800);

      final list = await fees.balances(yearId);
      expect(list, hasLength(2));
      final open = list.firstWhere((b) => b.studentId == openStudent);
      expect(open.due, a.due);
      expect(open.paid, a.paid);
      expect(open.overdue, a.overdue);
      expect(list.firstWhere((b) => b.studentId == scStudent).due, sc.due);
    });

    test('fee reports add up', () async {
      await setFees();
      await fees.takePayment(
        studentId: openStudent,
        academicYearId: yearId,
        byHead: {headId['Admission fee']!: 500, headId['Tuition fee']!: 1000},
        mode: PaymentMode.cash,
        receivedOn: today,
      );
      final cancelled = await fees.takePayment(
        studentId: scStudent,
        academicYearId: yearId,
        byHead: {headId['Admission fee']!: 500},
        mode: PaymentMode.upi,
        receivedOn: today,
      );
      await fees.cancelReceipt(cancelled, 'Wrong entry');
      final reports = FeeReports(AppLocalizationsEn(), fees, modeLabel: (m) => m.name);

      final book = await reports.dayBook(from: today, to: today);
      expect(book.dataRowCount, 2);
      expect(book.notes, contains('Total: Rs. 1,500'));

      final heads = await reports.headWise(from: today, to: today);
      expect(heads.rows.last.cells.last, '1500');

      final summary = await reports.classSummary(yearId, '2026-27');
      final total = summary.rows.last.cells;
      expect(total.sublist(2), ['2', '5600', '1500', '4100', '4100']);

      final defaulters = await reports.defaulters(yearId, '2026-27');
      expect(defaulters.dataRowCount, 2);
      expect(defaulters.hasGroups, isTrue);
    });
  });
}
