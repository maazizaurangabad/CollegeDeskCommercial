import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/org_scoped_repository.dart';
import '../../../core/ids/uuid7.dart';
import '../../../core/validation/mobile.dart';
import '../../../platform/data/app_settings_repository.dart';
import '../../students/data/student_repository.dart';
import '../../students/domain/student_models.dart';
import '../domain/fee_models.dart';

/// Fees: heads, what each class pays, concessions, payments and receipts.
/// Every rule lives here, whatever screen calls it.
class FeeRepository extends OrgScopedRepository {
  FeeRepository(super.db, super.session, this.settings, this.students, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppSettingsRepository settings;
  final StudentRepository students;
  final DateTime Function() _clock;

  static const receiptPrefixKey = 'fees.receipt_prefix';
  static const defaultReceiptPrefix = 'REC';

  /// Offered the first time fees are opened; each can be renamed or switched off.
  static const defaultHeads = [
    'Admission fee',
    'Tuition fee',
    'Term fee',
    'Examination fee',
    'Library fee',
    'Laboratory fee',
    'Gymkhana / Sports fee',
    'Other fee',
  ];

  // ================================================================== heads

  /// All heads in order, switched-off ones included. Defaults are added once.
  Future<List<FeeHead>> heads() async {
    var rows = await _headRows();
    if (rows.isEmpty) {
      await db.transaction(() async {
        for (var i = 0; i < defaultHeads.length; i++) {
          await _insertHead(defaultHeads[i], (i + 1) * 10);
        }
      });
      rows = await _headRows();
    }
    return [for (final r in rows) FeeHead(id: r.id, name: r.name, displayOrder: r.displayOrder, isActive: r.isActive)];
  }

  Future<List<FeeHeadRow>> _headRows() => (db.select(db.feeHeads)
        ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.displayOrder), (t) => OrderingTerm.asc(t.name)]))
      .get();

  Future<String> addHead(String name) {
    return db.transaction(() async {
      final clean = name.trim();
      await _checkName(clean);
      final existing = await heads();
      return _insertHead(clean, existing.isEmpty ? 10 : existing.last.displayOrder + 10);
    });
  }

  Future<String> _insertHead(String name, int order) async {
    final ts = now();
    final id = Uuid7.generate(ts);
    await db.into(db.feeHeads).insert(FeeHeadsCompanion.insert(
          id: id,
          organizationId: orgId,
          createdAt: ts,
          updatedAt: ts,
          createdBy: Value(session.userId),
          updatedBy: Value(session.userId),
          deviceId: session.deviceId,
          name: name,
          displayOrder: Value(order),
        ));
    await changes.record(table: 'fee_heads', rowId: id, operation: 'insert', after: {'name': name, 'order': order});
    return id;
  }

  Future<void> _checkName(String name, {String? exceptId}) async {
    if (name.isEmpty) throw const FeeException(FeeIssue.emptyName);
    final rows = await _headRows();
    if (rows.any((r) => r.id != exceptId && r.name.toLowerCase() == name.toLowerCase())) {
      throw const FeeException(FeeIssue.duplicateName);
    }
  }

  Future<void> updateHead(String id, {String? name, bool? isActive}) {
    return db.transaction(() async {
      final row = await _headRow(id);
      final newName = name?.trim() ?? row.name;
      if (name != null) await _checkName(newName, exceptId: id);
      await (db.update(db.feeHeads)..where((t) => t.id.equals(id))).write(FeeHeadsCompanion(
        name: Value(newName),
        isActive: Value(isActive ?? row.isActive),
        updatedAt: Value(now()),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(row.rowVersion + 1),
      ));
      await changes.record(
        table: 'fee_heads',
        rowId: id,
        operation: 'update',
        before: {'name': row.name, 'active': row.isActive},
        after: {'name': newName, 'active': isActive ?? row.isActive},
      );
    });
  }

  /// Moves a head up (-1) or down (+1) in the list.
  Future<void> moveHead(String id, int direction) {
    return db.transaction(() async {
      final list = await _headRows();
      final i = list.indexWhere((r) => r.id == id);
      final j = i + direction;
      if (i < 0 || j < 0 || j >= list.length) return;
      final reordered = [...list];
      final item = reordered.removeAt(i);
      reordered.insert(j, item);
      for (var k = 0; k < reordered.length; k++) {
        final order = (k + 1) * 10;
        if (reordered[k].displayOrder == order) continue;
        await (db.update(db.feeHeads)..where((t) => t.id.equals(reordered[k].id)))
            .write(FeeHeadsCompanion(displayOrder: Value(order), updatedAt: Value(now())));
      }
      await changes.record(table: 'fee_heads', rowId: id, operation: 'reorder', after: {'direction': direction});
    });
  }

  /// Only a head never used in a structure, concession or receipt can be deleted;
  /// otherwise switch it off.
  Future<void> deleteHead(String id) {
    return db.transaction(() async {
      final row = await _headRow(id);
      final inItems = await (db.select(db.feeStructureItems)
            ..where((t) => t.organizationId.equals(orgId) & t.headId.equals(id) & t.deletedAt.isNull())
            ..limit(1))
          .get();
      final inLines = await (db.select(db.feeReceiptLines)
            ..where((t) => t.organizationId.equals(orgId) & t.headId.equals(id))
            ..limit(1))
          .get();
      final inAdjust = await (db.select(db.studentFeeAdjustments)
            ..where((t) => t.organizationId.equals(orgId) & t.headId.equals(id) & t.deletedAt.isNull())
            ..limit(1))
          .get();
      if (inItems.isNotEmpty || inLines.isNotEmpty || inAdjust.isNotEmpty) throw const FeeException(FeeIssue.headInUse);
      await (db.update(db.feeHeads)..where((t) => t.id.equals(id)))
          .write(FeeHeadsCompanion(deletedAt: Value(now()), updatedAt: Value(now())));
      await changes.record(table: 'fee_heads', rowId: id, operation: 'delete', after: {'name': row.name});
    });
  }

  Future<FeeHeadRow> _headRow(String id) async {
    final row = await (db.select(db.feeHeads)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
        .getSingleOrNull();
    if (row == null) throw const FeeException(FeeIssue.notFound);
    return row;
  }

  // ============================================================= structures

  Future<List<FeeStructure>> structures(String academicYearId) async {
    final rows = await (db.select(db.feeStructures)
          ..where((t) => t.organizationId.equals(orgId) & t.academicYearId.equals(academicYearId) & t.deletedAt.isNull()))
        .get();
    if (rows.isEmpty) return [];
    final items = await (db.select(db.feeStructureItems)
          ..where((t) =>
              t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.structureId.isIn(rows.map((r) => r.id))))
        .get();
    return [
      for (final r in rows)
        FeeStructure(
          id: r.id,
          academicYearId: r.academicYearId,
          programId: r.programId,
          category: r.category,
          amounts: {
            for (final i in items)
              if (i.structureId == r.id && i.amount != 0) i.headId: i.amount,
          },
        ),
    ];
  }

  static String? _cleanCategory(String? c) => (c == null || c.trim().isEmpty) ? null : c.trim();

  static bool _sameCategory(String? a, String? b) =>
      (_cleanCategory(a)?.toLowerCase()) == (_cleanCategory(b)?.toLowerCase());

  /// Saves what [programId] pays in the year, for everyone ([category] null)
  /// or for one category. Replaces the earlier amounts for the same class
  /// and category. Returns the structure id.
  Future<String> saveStructure({
    required String academicYearId,
    required String programId,
    String? category,
    required Map<String, int> amounts,
  }) {
    return db.transaction(() async {
      if (amounts.values.any((a) => a < 0)) throw const FeeException(FeeIssue.negativeAmount);
      final cat = _cleanCategory(category);
      final ts = now();
      final existing = (await (db.select(db.feeStructures)
                ..where((t) =>
                    t.organizationId.equals(orgId) &
                    t.academicYearId.equals(academicYearId) &
                    t.programId.equals(programId) &
                    t.deletedAt.isNull()))
              .get())
          .where((r) => _sameCategory(r.category, cat))
          .firstOrNull;
      final String id;
      var before = <String, int>{};
      if (existing == null) {
        id = Uuid7.generate(ts);
        await db.into(db.feeStructures).insert(FeeStructuresCompanion.insert(
              id: id,
              organizationId: orgId,
              createdAt: ts,
              updatedAt: ts,
              createdBy: Value(session.userId),
              updatedBy: Value(session.userId),
              deviceId: session.deviceId,
              academicYearId: academicYearId,
              programId: programId,
              category: Value(cat),
            ));
      } else {
        id = existing.id;
        final old = await (db.select(db.feeStructureItems)
              ..where((t) => t.structureId.equals(id) & t.deletedAt.isNull()))
            .get();
        before = {for (final o in old) o.headId: o.amount};
        await (db.update(db.feeStructureItems)..where((t) => t.structureId.equals(id) & t.deletedAt.isNull()))
            .write(FeeStructureItemsCompanion(deletedAt: Value(ts), updatedAt: Value(ts)));
        await (db.update(db.feeStructures)..where((t) => t.id.equals(id))).write(FeeStructuresCompanion(
          updatedAt: Value(ts),
          updatedBy: Value(session.userId),
          deviceId: Value(session.deviceId),
          rowVersion: Value(existing.rowVersion + 1),
        ));
      }
      for (final e in amounts.entries.where((e) => e.value > 0)) {
        await db.into(db.feeStructureItems).insert(FeeStructureItemsCompanion.insert(
              id: Uuid7.generate(ts),
              organizationId: orgId,
              createdAt: ts,
              updatedAt: ts,
              createdBy: Value(session.userId),
              updatedBy: Value(session.userId),
              deviceId: session.deviceId,
              structureId: id,
              headId: e.key,
              amount: e.value,
            ));
      }
      await changes.record(
        table: 'fee_structures',
        rowId: id,
        operation: existing == null ? 'insert' : 'update',
        before: existing == null ? null : {'amounts': before.toString()},
        after: {
          'year': academicYearId,
          'program': programId,
          'category': cat,
          'amounts': {for (final e in amounts.entries.where((e) => e.value > 0)) e.key: e.value}.toString(),
        },
      );
      return id;
    });
  }

  Future<void> deleteStructure(String id) {
    return db.transaction(() async {
      final ts = now();
      await (db.update(db.feeStructures)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
          .write(FeeStructuresCompanion(deletedAt: Value(ts), updatedAt: Value(ts)));
      await (db.update(db.feeStructureItems)..where((t) => t.structureId.equals(id) & t.deletedAt.isNull()))
          .write(FeeStructureItemsCompanion(deletedAt: Value(ts), updatedAt: Value(ts)));
      await changes.record(table: 'fee_structures', rowId: id, operation: 'delete', after: {});
    });
  }

  /// Copies structures from another year into [toYearId], matching classes
  /// by name. Classes that already have amounts are left alone.
  /// Returns how many structures were copied.
  Future<int> copyStructures({required String fromYearId, required String toYearId}) async {
    final from = await structures(fromYearId);
    final to = await structures(toYearId);
    var copied = 0;
    for (final s in from) {
      if (to.any((t) => t.programId == s.programId && _sameCategory(t.category, s.category))) continue;
      await saveStructure(academicYearId: toYearId, programId: s.programId, category: s.category, amounts: s.amounts);
      copied++;
    }
    return copied;
  }

  // ============================================================= due dates

  /// Installments of a structure, earliest first.
  Future<List<FeeDueDate>> dueDates(String structureId) async {
    final rows = await (db.select(db.feeDueDates)
          ..where((t) => t.organizationId.equals(orgId) & t.structureId.equals(structureId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .get();
    return [for (final r in rows) FeeDueDate(label: r.label, dueDate: r.dueDate, amount: r.amount)];
  }

  /// Replaces a structure's installments. An empty list means the whole
  /// amount is due at once.
  Future<void> saveDueDates(String structureId, List<FeeDueDate> dates) {
    return db.transaction(() async {
      if (dates.any((d) => d.amount < 0)) throw const FeeException(FeeIssue.negativeAmount);
      final ts = now();
      await (db.update(db.feeDueDates)
            ..where((t) => t.organizationId.equals(orgId) & t.structureId.equals(structureId) & t.deletedAt.isNull()))
          .write(FeeDueDatesCompanion(deletedAt: Value(ts), updatedAt: Value(ts)));
      for (final d in dates) {
        await db.into(db.feeDueDates).insert(FeeDueDatesCompanion.insert(
              id: Uuid7.generate(ts),
              organizationId: orgId,
              createdAt: ts,
              updatedAt: ts,
              createdBy: Value(session.userId),
              updatedBy: Value(session.userId),
              deviceId: session.deviceId,
              structureId: structureId,
              label: d.label.trim().isEmpty ? 'Installment' : d.label.trim(),
              dueDate: DateTime.utc(d.dueDate.year, d.dueDate.month, d.dueDate.day),
              amount: d.amount,
            ));
      }
      await changes.record(table: 'fee_due_dates', rowId: structureId, operation: 'replace', after: {
        'dates': [
          for (final d in dates) '${DateTime.utc(d.dueDate.year, d.dueDate.month, d.dueDate.day).toIso8601String().substring(0, 10)}=${d.amount}',
        ].join(', '),
      });
    });
  }

  // =============================================================== balances

  /// Every current student of the year with what is due, paid and overdue.
  /// Worked out for all students at once (same rules as [account]).
  Future<List<StudentFeeBalance>> balances(String academicYearId) async {
    final enrollments = await (db.select(db.enrollments)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.academicYearId.equals(academicYearId) &
              t.deletedAt.isNull() &
              t.status.isIn(yearMemberStatuses)))
        .get();
    if (enrollments.isEmpty) return [];
    final ids = enrollments.map((e) => e.studentId).toSet();
    final names = await students.namesFor(ids);
    final categoryOf = {
      for (final r in await (db.select(db.students)
            ..where((t) => t.organizationId.equals(orgId) & t.id.isIn(ids) & t.deletedAt.isNull()))
          .get())
        r.id: _cleanCategory(r.category),
    };
    final divisions = {for (final d in await (db.select(db.divisions)..where((t) => t.organizationId.equals(orgId))).get()) d.id: d};
    final programs = {for (final p in await (db.select(db.programs)..where((t) => t.organizationId.equals(orgId))).get()) p.id: p};
    final structures = await this.structures(academicYearId);
    final dates = <String, List<FeeDueDate>>{for (final st in structures) st.id: await dueDates(st.id)};

    final adjustments = await (db.select(db.studentFeeAdjustments)
          ..where((t) =>
              t.organizationId.equals(orgId) & t.academicYearId.equals(academicYearId) & t.deletedAt.isNull()))
        .get();
    final adjust = <String, Map<String, int>>{};
    for (final a in adjustments) {
      final m = adjust[a.studentId] ??= {};
      m[a.headId] = (m[a.headId] ?? 0) + a.amount;
    }
    final paidRows = await (db.select(db.feeReceipts)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.academicYearId.equals(academicYearId) &
              t.deletedAt.isNull() &
              t.status.equals('issued')))
        .get();
    final paid = <String, int>{};
    for (final r in paidRows) {
      paid[r.studentId] = (paid[r.studentId] ?? 0) + r.totalAmount;
    }
    final mobiles = await _primaryMobiles(ids);
    final today = _clock();

    final out = <StudentFeeBalance>[];
    for (final e in enrollments) {
      final student = names[e.studentId];
      final division = divisions[e.divisionId];
      if (student == null || division == null) continue;
      final category = categoryOf[e.studentId];
      final forClass = structures.where((st) => st.programId == division.programId).toList();
      final structure = forClass.where((st) => st.category != null && _sameCategory(st.category, category)).firstOrNull ??
          forClass.where((st) => st.category == null).firstOrNull;
      final base = structure?.amounts ?? const <String, int>{};
      final extra = adjust[e.studentId] ?? const <String, int>{};
      var due = 0;
      for (final head in {...base.keys, ...extra.keys}) {
        final v = (base[head] ?? 0) + (extra[head] ?? 0);
        if (v > 0) due += v;
      }
      out.add(StudentFeeBalance(
        studentId: e.studentId,
        name: student.fullName,
        classLabel: '${programs[division.programId]?.name ?? ''} ${division.name}'.trim(),
        divisionId: division.id,
        programId: division.programId,
        rollNumber: e.rollNumber,
        category: category,
        mobile: mobiles[e.studentId],
        due: due,
        paid: paid[e.studentId] ?? 0,
        dueByToday: dueBy(structure == null ? const [] : dates[structure.id] ?? const [], today, due),
      ));
    }
    out.sort((a, b) {
      final c = a.classLabel.compareTo(b.classLabel);
      if (c != 0) return c;
      final r = (a.rollNumber ?? 9999).compareTo(b.rollNumber ?? 9999);
      return r != 0 ? r : a.name.compareTo(b.name);
    });
    return out;
  }

  /// studentId -> primary guardian's mobile (or any guardian's), ten digits.
  Future<Map<String, String>> _primaryMobiles(Set<String> ids) async {
    final links = await (db.select(db.studentGuardians)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.studentId.isIn(ids)))
        .get();
    if (links.isEmpty) return {};
    final guardians = {
      for (final g in await (db.select(db.guardians)
            ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.id.isIn(links.map((l) => l.guardianId))))
          .get())
        g.id: g,
    };
    final out = <String, String>{};
    for (final l in links..sort((a, b) => (b.isPrimary ? 1 : 0).compareTo(a.isPrimary ? 1 : 0))) {
      if (out.containsKey(l.studentId)) continue;
      final g = guardians[l.guardianId];
      final m = g?.mobile ?? g?.altMobile;
      if (m != null && MobileNumber.isValid(m)) out[l.studentId] = MobileNumber.normalize(m);
    }
    return out;
  }

  // ================================================================ account

  /// The student's fees for the year: what applies, concessions, what is paid.
  Future<FeeAccount> account(String studentId, String academicYearId) async {
    final detail = await students.load(studentId, includeDeleted: true);
    if (detail == null) throw const FeeException(FeeIssue.notFound);
    final year = await (db.select(db.academicYears)..where((t) => t.id.equals(academicYearId))).getSingleOrNull();
    final name = (await students.namesFor([studentId]))[studentId]?.fullName ??
        [detail.draft.firstName, detail.draft.middleName, detail.draft.lastName].where((s) => s.isNotEmpty).join(' ');

    final enrollment = detail.enrollments.where((e) => e.academicYearId == academicYearId).firstOrNull;
    String? programId;
    var classLabel = '';
    if (enrollment != null) {
      final division =
          await (db.select(db.divisions)..where((t) => t.id.equals(enrollment.divisionId))).getSingleOrNull();
      programId = division?.programId;
      if (division != null) {
        final program =
            await (db.select(db.programs)..where((t) => t.id.equals(division.programId))).getSingleOrNull();
        classLabel = '${program?.name ?? ''} ${division.name}'.trim();
      }
    }

    final category = _cleanCategory(detail.draft.category);
    FeeStructure? structure;
    if (programId != null) {
      final forClass = (await structures(academicYearId)).where((s) => s.programId == programId).toList();
      structure = forClass.where((s) => s.category != null && _sameCategory(s.category, category)).firstOrNull ??
          forClass.where((s) => s.category == null).firstOrNull;
    }

    final heads = await this.heads();
    final headName = {for (final h in heads) h.id: h.name};
    final adjustRows = await (db.select(db.studentFeeAdjustments)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.studentId.equals(studentId) &
              t.academicYearId.equals(academicYearId) &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    final receipts = await receiptsOf(studentId: studentId, academicYearId: academicYearId);

    final fromStructure = structure?.amounts ?? const <String, int>{};
    final adjust = <String, int>{};
    for (final a in adjustRows) {
      adjust[a.headId] = (adjust[a.headId] ?? 0) + a.amount;
    }
    final paid = <String, int>{};
    final paidNames = <String, String>{};
    for (final r in receipts.where((r) => !r.isCancelled)) {
      for (final l in r.lines) {
        paid[l.headId] = (paid[l.headId] ?? 0) + l.amount;
        paidNames[l.headId] = l.headName;
      }
    }
    final used = {...fromStructure.keys, ...adjust.keys, ...paid.keys};
    final order = [for (final h in heads) h.id];
    final ids = used.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a), ib = order.indexOf(b);
        return (ia < 0 ? 1 << 20 : ia).compareTo(ib < 0 ? 1 << 20 : ib);
      });

    return FeeAccount(
      studentId: studentId,
      studentName: name,
      academicYearId: academicYearId,
      academicYearLabel: year?.label ?? '',
      classLabel: classLabel,
      grNumber: detail.identifier(IdentifierType.grNumber),
      programId: programId,
      category: category,
      structureId: structure?.id,
      structureCategory: structure?.category,
      dueDates: structure == null ? const [] : await dueDates(structure.id),
      today: _clock(),
      lines: [
        for (final id in ids)
          FeeLine(
            headId: id,
            headName: headName[id] ?? paidNames[id] ?? '',
            fromStructure: fromStructure[id] ?? 0,
            adjustment: adjust[id] ?? 0,
            paid: paid[id] ?? 0,
          ),
      ],
      adjustments: [
        for (final a in adjustRows)
          FeeAdjustment(
            id: a.id,
            headId: a.headId,
            headName: headName[a.headId] ?? '',
            amount: a.amount,
            reason: a.reason,
            createdAt: a.createdAt,
          ),
      ],
      receipts: receipts,
    );
  }

  /// A concession (negative [amount]) or extra charge (positive) on one head.
  Future<void> addAdjustment({
    required String studentId,
    required String academicYearId,
    required String headId,
    required int amount,
    required String reason,
  }) {
    return db.transaction(() async {
      if (amount == 0) throw const FeeException(FeeIssue.noAmount);
      if (reason.trim().isEmpty) throw const FeeException(FeeIssue.noReason);
      final ts = now();
      final id = Uuid7.generate(ts);
      await db.into(db.studentFeeAdjustments).insert(StudentFeeAdjustmentsCompanion.insert(
            id: id,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            studentId: studentId,
            academicYearId: academicYearId,
            headId: headId,
            amount: amount,
            reason: reason.trim(),
          ));
      await changes.record(
        table: 'student_fee_adjustments',
        rowId: id,
        operation: 'insert',
        after: {'student_id': studentId, 'year': academicYearId, 'head_id': headId, 'amount': amount, 'reason': reason.trim()},
      );
    });
  }

  Future<void> deleteAdjustment(String id) {
    return db.transaction(() async {
      final row = await (db.select(db.studentFeeAdjustments)
            ..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
          .getSingleOrNull();
      if (row == null) throw const FeeException(FeeIssue.notFound);
      await (db.update(db.studentFeeAdjustments)..where((t) => t.id.equals(id)))
          .write(StudentFeeAdjustmentsCompanion(deletedAt: Value(now()), updatedAt: Value(now())));
      await changes.record(
        table: 'student_fee_adjustments',
        rowId: id,
        operation: 'delete',
        after: {'student_id': row.studentId, 'amount': row.amount, 'reason': row.reason},
      );
    });
  }

  // =============================================================== receipts

  Future<String> receiptPrefix() async {
    final v = (await settings.getValue(receiptPrefixKey))?.trim() ?? '';
    return v.isEmpty ? defaultReceiptPrefix : v;
  }

  Future<void> setReceiptPrefix(String prefix) {
    final clean = prefix.trim().replaceAll('/', '-');
    return settings.setValue(receiptPrefixKey, clean.isEmpty ? defaultReceiptPrefix : clean);
  }

  /// Records a payment and returns the new receipt's id. [byHead] is
  /// headId -> amount; amounts above what is due are allowed (the screen
  /// asks first), negative amounts are not.
  Future<String> takePayment({
    required String studentId,
    required String academicYearId,
    required Map<String, int> byHead,
    required PaymentMode mode,
    required DateTime receivedOn,
    String? reference,
    String? note,
  }) async {
    if (byHead.values.any((a) => a < 0)) throw const FeeException(FeeIssue.negativeAmount);
    final lines = {for (final e in byHead.entries) if (e.value > 0) e.key: e.value};
    if (lines.isEmpty) throw const FeeException(FeeIssue.noAmount);
    final today = _clock();
    if (DateTime(receivedOn.year, receivedOn.month, receivedOn.day).isAfter(DateTime(today.year, today.month, today.day))) {
      throw const FeeException(FeeIssue.futureDate);
    }
    final before = await account(studentId, academicYearId);
    final headName = {for (final h in await heads()) h.id: h.name};
    final total = lines.values.fold(0, (a, b) => a + b);
    final prefix = await receiptPrefix();

    return db.transaction(() async {
      final serial = await _nextSerial(before.academicYearLabel);
      final label = '$prefix/${before.academicYearLabel}/${serial.toString().padLeft(4, '0')}';
      final ts = now();
      final id = Uuid7.generate(ts);
      await db.into(db.feeReceipts).insert(FeeReceiptsCompanion.insert(
            id: id,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            serialNo: serial,
            serialLabel: label,
            academicYearId: academicYearId,
            academicYearLabel: before.academicYearLabel,
            studentId: studentId,
            studentName: before.studentName,
            classLabel: Value(before.classLabel),
            grNumber: Value(before.grNumber),
            receivedOn: DateTime.utc(receivedOn.year, receivedOn.month, receivedOn.day),
            totalAmount: total,
            balanceAfter: Value(before.balance - total),
            mode: mode.name,
            reference: Value(_opt(reference)),
            note: Value(_opt(note)),
          ));
      for (final e in lines.entries) {
        await db.into(db.feeReceiptLines).insert(FeeReceiptLinesCompanion.insert(
              id: Uuid7.generate(ts),
              organizationId: orgId,
              createdAt: ts,
              updatedAt: ts,
              createdBy: Value(session.userId),
              updatedBy: Value(session.userId),
              deviceId: session.deviceId,
              receiptId: id,
              headId: e.key,
              headName: headName[e.key] ?? '',
              amount: e.value,
            ));
      }
      await changes.record(table: 'fee_receipts', rowId: id, operation: 'insert', after: {
        'serial': label,
        'student_id': studentId,
        'total': total,
        'mode': mode.name,
        'received_on': DateTime.utc(receivedOn.year, receivedOn.month, receivedOn.day).toIso8601String().substring(0, 10),
      });
      return id;
    });
  }

  static String? _opt(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<int> _nextSerial(String yearLabel) async {
    final name = 'fee.receipt.$yearLabel';
    final seq = await (db.select(db.sequences)..where((t) => t.organizationId.equals(orgId) & t.name.equals(name)))
        .getSingleOrNull();
    if (seq == null) {
      await db.into(db.sequences).insert(SequencesCompanion.insert(organizationId: orgId, name: name, nextValue: 2));
      return 1;
    }
    await (db.update(db.sequences)..where((t) => t.organizationId.equals(orgId) & t.name.equals(name)))
        .write(SequencesCompanion(nextValue: Value(seq.nextValue + 1)));
    return seq.nextValue;
  }

  Future<FeeReceiptRecord?> receipt(String id) async {
    final list = await _receipts((t) => t.id.equals(id) & t.organizationId.equals(orgId));
    return list.firstOrNull;
  }

  Future<List<FeeReceiptRecord>> receiptsOf({required String studentId, String? academicYearId}) => _receipts((t) {
        var e = t.organizationId.equals(orgId) & t.studentId.equals(studentId) & t.deletedAt.isNull();
        if (academicYearId != null) e = e & t.academicYearId.equals(academicYearId);
        return e;
      });

  /// The register: receipts between two dates (both included), newest first.
  Future<List<FeeReceiptRecord>> receipts({DateTime? from, DateTime? to, String query = ''}) async {
    final list = await _receipts((t) {
      var e = t.organizationId.equals(orgId) & t.deletedAt.isNull();
      if (from != null) e = e & t.receivedOn.isBiggerOrEqualValue(DateTime.utc(from.year, from.month, from.day));
      if (to != null) e = e & t.receivedOn.isSmallerOrEqualValue(DateTime.utc(to.year, to.month, to.day));
      return e;
    });
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list
        .where((r) => '${r.studentName} ${r.serialLabel} ${r.grNumber ?? ''} ${r.classLabel} ${r.reference ?? ''}'
            .toLowerCase()
            .contains(q))
        .toList();
  }

  Future<List<FeeReceiptRecord>> _receipts(Expression<bool> Function($FeeReceiptsTable t) filter) async {
    final rows = await (db.select(db.feeReceipts)
          ..where(filter)
          ..orderBy([(t) => OrderingTerm.desc(t.receivedOn), (t) => OrderingTerm.desc(t.serialNo)]))
        .get();
    if (rows.isEmpty) return [];
    final lines = await (db.select(db.feeReceiptLines)
          ..where((t) => t.deletedAt.isNull() & t.receiptId.isIn(rows.map((r) => r.id)))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return [
      for (final r in rows)
        FeeReceiptRecord(
          id: r.id,
          serialLabel: r.serialLabel,
          academicYearId: r.academicYearId,
          academicYearLabel: r.academicYearLabel,
          studentId: r.studentId,
          studentName: r.studentName,
          classLabel: r.classLabel,
          grNumber: r.grNumber,
          receivedOn: r.receivedOn,
          total: r.totalAmount,
          balanceAfter: r.balanceAfter,
          mode: PaymentMode.byName(r.mode),
          reference: r.reference,
          note: r.note,
          status: r.status == 'cancelled' ? ReceiptStatus.cancelled : ReceiptStatus.issued,
          cancelReason: r.cancelReason,
          printCount: r.printCount,
          createdAt: r.createdAt,
          createdBy: r.createdBy,
          lines: [
            for (final l in lines.where((l) => l.receiptId == r.id))
              FeeReceiptLine(headId: l.headId, headName: l.headName, amount: l.amount),
          ],
        ),
    ];
  }

  /// Cancels a receipt (wrong entry, cheque bounced). It stays in the
  /// register and its number is never given again.
  Future<void> cancelReceipt(String id, String reason) {
    return db.transaction(() async {
      if (reason.trim().isEmpty) throw const FeeException(FeeIssue.noReason);
      final row = await (db.select(db.feeReceipts)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
          .getSingleOrNull();
      if (row == null) throw const FeeException(FeeIssue.notFound);
      if (row.status == 'cancelled') return;
      await (db.update(db.feeReceipts)..where((t) => t.id.equals(id))).write(FeeReceiptsCompanion(
        status: const Value('cancelled'),
        cancelReason: Value(reason.trim()),
        updatedAt: Value(now()),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(row.rowVersion + 1),
      ));
      await changes.record(
        table: 'fee_receipts',
        rowId: id,
        operation: 'cancel',
        before: {'status': row.status},
        after: {'status': 'cancelled', 'reason': reason.trim()},
      );
    });
  }

  Future<void> recordPrint(String id) async {
    final row = await (db.select(db.feeReceipts)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
        .getSingleOrNull();
    if (row == null) return;
    await (db.update(db.feeReceipts)..where((t) => t.id.equals(id)))
        .write(FeeReceiptsCompanion(printCount: Value(row.printCount + 1)));
  }

  /// Collected on [date] (cancelled receipts not counted), per payment mode.
  Future<({int total, int count, Map<PaymentMode, int> byMode})> collectedOn(DateTime date) async {
    final list = (await receipts(from: date, to: date)).where((r) => !r.isCancelled);
    final byMode = <PaymentMode, int>{};
    var total = 0, count = 0;
    for (final r in list) {
      total += r.total;
      count++;
      byMode[r.mode] = (byMode[r.mode] ?? 0) + r.total;
    }
    return (total: total, count: count, byMode: byMode);
  }
}
