import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/org_scoped_repository.dart';
import '../../../core/ids/uuid7.dart';
import '../../../core/security/field_cipher.dart';
import '../../../core/validation/aadhaar.dart';
import '../../../core/validation/mobile.dart';
import '../domain/student_models.dart';

/// The one place student records are read and written.
/// Every rule (unique numbers and rolls, Aadhaar check, one active
/// enrollment) is enforced here, whatever screen or import calls it.
class StudentRepository extends OrgScopedRepository {
  StudentRepository(super.db, super.session, this.cipher);

  final FieldCipher cipher;

  static const _codeSequence = 'student_code';
  static const recycleBinDays = 30;

  // ============================================================== reading

  /// Students matching [query] (every word must match a name, code,
  /// identifier or guardian mobile), with their placement in [academicYearId].
  Future<List<StudentListItem>> list({
    String query = '',
    String? academicYearId,
    StudentStatus? status,
    int limit = 50000,
  }) async {
    final tokens = query
        .toLowerCase()
        .replaceAll(RegExp(r'[%_]'), '')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final select = db.select(db.students)
      ..where((t) {
        var condition = t.organizationId.equals(orgId) & t.deletedAt.isNull();
        if (status != null) condition = condition & t.status.equals(status.name);
        for (final token in tokens) {
          condition = condition & t.searchText.like('%$token%');
        }
        return condition;
      })
      ..orderBy([(t) => OrderingTerm.asc(t.firstName), (t) => OrderingTerm.asc(t.lastName)])
      ..limit(limit);
    final rows = await select.get();

    final placements = <String, EnrollmentRow>{};
    if (academicYearId != null) {
      final enrollments = await (db.select(db.enrollments)
            ..where((t) =>
                t.organizationId.equals(orgId) &
                t.academicYearId.equals(academicYearId) &
                t.status.equals(EnrollmentStatus.active.name) &
                t.deletedAt.isNull()))
          .get();
      for (final e in enrollments) {
        placements[e.studentId] = e;
      }
    }
    final mobiles = await _primaryMobiles();
    final grs = {
      for (final i in await (db.select(db.studentIdentifiers)
            ..where((t) =>
                t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.idType.equals(IdentifierType.grNumber.code)))
          .get())
        i.studentId: i.idValue,
    };

    return [
      for (final r in rows)
        StudentListItem(
          id: r.id,
          displayCode: r.displayCode,
          fullName: _fullName(r),
          status: _status(r.status),
          gender: r.gender,
          photoFileName: r.photoFileName,
          divisionId: placements[r.id]?.divisionId,
          rollNumber: placements[r.id]?.rollNumber,
          primaryMobile: mobiles[r.id],
          grNumber: grs[r.id],
          dateOfBirth: r.dateOfBirth,
        ),
    ];
  }

  /// Active students whose birthday is on [date] (day and month).
  Future<List<StudentListItem>> birthdaysOn(DateTime date) async {
    final rows = await (db.select(db.students)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.deletedAt.isNull() &
              t.status.equals(StudentStatus.active.name) &
              t.dateOfBirth.isNotNull()))
        .get();
    return [
      for (final r in rows)
        if (r.dateOfBirth!.month == date.month && r.dateOfBirth!.day == date.day)
          StudentListItem(
            id: r.id,
            displayCode: r.displayCode,
            fullName: _fullName(r),
            status: _status(r.status),
            photoFileName: r.photoFileName,
          ),
    ];
  }

  /// Names and codes for a set of students (dashboard lists).
  Future<Map<String, StudentListItem>> namesFor(Iterable<String> ids) async {
    final list = ids.toSet();
    if (list.isEmpty) return {};
    final rows = await (db.select(db.students)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.id.isIn(list)))
        .get();
    return {
      for (final r in rows)
        r.id: StudentListItem(
          id: r.id,
          displayCode: r.displayCode,
          fullName: _fullName(r),
          status: _status(r.status),
          photoFileName: r.photoFileName,
        ),
    };
  }

  Future<int> countActive() async {
    final count = db.students.id.count();
    final query = db.selectOnly(db.students)
      ..addColumns([count])
      ..where(db.students.organizationId.equals(orgId) &
          db.students.deletedAt.isNull() &
          db.students.status.equals(StudentStatus.active.name));
    return (await query.getSingle()).read(count) ?? 0;
  }

  Future<StudentDetail?> load(String studentId, {bool includeDeleted = false}) async {
    final row = await (db.select(db.students)
          ..where((t) =>
              t.id.equals(studentId) &
              t.organizationId.equals(orgId) &
              (includeDeleted ? const Constant(true) : t.deletedAt.isNull())))
        .getSingleOrNull();
    if (row == null) return null;

    final links = await (db.select(db.studentGuardians)
          ..where((t) => t.organizationId.equals(orgId) & t.studentId.equals(studentId) & t.deletedAt.isNull()))
        .get();
    final guardianRows = links.isEmpty
        ? <GuardianRow>[]
        : await (db.select(db.guardians)
              ..where((t) => t.organizationId.equals(orgId) & t.id.isIn(links.map((l) => l.guardianId))))
            .get();
    final guardians = <GuardianInfo>[
      for (final link in links)
        for (final g in guardianRows.where((g) => g.id == link.guardianId))
          GuardianInfo(
            id: g.id,
            name: g.name,
            relation: g.relation,
            isPrimary: link.isPrimary,
            mobile: g.mobile,
            altMobile: g.altMobile,
            email: g.email,
            occupation: g.occupation,
          ),
    ]..sort((a, b) => (b.isPrimary ? 1 : 0) - (a.isPrimary ? 1 : 0));

    final identifierRows = await _identifierRows(studentId);
    final identifiers = <IdentifierInfo>[
      for (final i in identifierRows)
        if (IdentifierType.fromCode(i.idType) case final type?)
          IdentifierInfo(
            type: type,
            display: type == IdentifierType.aadhaar ? Aadhaar.mask(i.lastFour ?? '????') : i.idValue,
          ),
    ];

    final enrollmentRows = await (db.select(db.enrollments)
          ..where((t) => t.organizationId.equals(orgId) & t.studentId.equals(studentId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.startDate)]))
        .get();
    final enrollments = [
      for (final e in enrollmentRows)
        EnrollmentInfo(
          id: e.id,
          academicYearId: e.academicYearId,
          divisionId: e.divisionId,
          rollNumber: e.rollNumber,
          startDate: e.startDate,
          endDate: e.endDate,
          status: EnrollmentStatus.values.firstWhere((s) => s.name == e.status, orElse: () => EnrollmentStatus.active),
        ),
    ];

    final active = enrollments.where((e) => e.status == EnrollmentStatus.active).firstOrNull;
    final draft = StudentDraft(
      firstName: row.firstName,
      middleName: row.middleName ?? '',
      lastName: row.lastName ?? '',
      altName: row.altName ?? '',
      gender: row.gender,
      dateOfBirth: row.dateOfBirth,
      placeOfBirth: row.placeOfBirth ?? '',
      nationality: row.nationality ?? '',
      motherTongue: row.motherTongue ?? '',
      category: row.category,
      caste: row.caste ?? '',
      subCaste: row.subCaste ?? '',
      bloodGroup: row.bloodGroup,
      heightCm: row.heightCm,
      weightKg: row.weightKg,
      measuredOn: row.measuredOn,
      address: row.address ?? '',
      photoFileName: row.photoFileName,
      admissionDate: row.admissionDate,
      previousSchool: row.previousSchool ?? '',
      notes: row.notes ?? '',
      guardians: [
        for (final g in guardians)
          GuardianDraft(
            id: g.id,
            name: g.name,
            relation: g.relation,
            mobile: g.mobile ?? '',
            altMobile: g.altMobile ?? '',
            email: g.email ?? '',
            occupation: g.occupation ?? '',
            isPrimary: g.isPrimary,
          ),
      ],
      identifiers: {
        for (final i in identifiers)
          if (i.type != IdentifierType.aadhaar) i.type: i.display,
      },
      divisionId: active?.divisionId,
      rollNumber: active?.rollNumber,
      extra: _decodeExtra(row.extraJson),
    );

    return StudentDetail(
      id: row.id,
      displayCode: row.displayCode,
      status: _status(row.status),
      draft: draft,
      guardians: guardians,
      identifiers: identifiers,
      enrollments: enrollments,
      leavingDate: row.leavingDate,
      leavingReason: row.leavingReason,
      deletedAt: row.deletedAt,
    );
  }

  /// Existing students that look like [draft]. Shown as a warning before saving.
  Future<List<DuplicateMatch>> findDuplicates(StudentDraft draft, {String? excludeId}) async {
    final found = <String, DuplicateReason>{};
    final name = draft.fullName.toLowerCase();

    if (draft.dateOfBirth != null && name.isNotEmpty) {
      final sameBirth = await (db.select(db.students)
            ..where((t) =>
                t.organizationId.equals(orgId) &
                t.deletedAt.isNull() &
                t.dateOfBirth.equals(_dateOnly(draft.dateOfBirth!))))
          .get();
      for (final s in sameBirth) {
        if (_fullName(s).toLowerCase() == name) found.putIfAbsent(s.id, () => DuplicateReason.sameNameAndBirthDate);
      }
    }

    for (final entry in draft.identifiers.entries) {
      final value = entry.value.trim();
      if (value.isEmpty) continue;
      final owner = await _identifierOwner(entry.key, value);
      if (owner != null) found.putIfAbsent(owner, () => DuplicateReason.sameIdentifier);
    }

    final first = draft.firstName.trim().toLowerCase();
    final last = draft.lastName.trim().toLowerCase();
    for (final g in draft.guardians) {
      if (g.mobile.trim().isEmpty) continue;
      final mobile = MobileNumber.normalize(g.mobile);
      final guardians = await (db.select(db.guardians)
            ..where((t) => t.organizationId.equals(orgId) & t.mobile.equals(mobile) & t.deletedAt.isNull()))
          .get();
      if (guardians.isEmpty) continue;
      final links = await (db.select(db.studentGuardians)
            ..where((t) => t.organizationId.equals(orgId) & t.guardianId.isIn(guardians.map((x) => x.id)) & t.deletedAt.isNull()))
          .get();
      for (final link in links) {
        final s = await _studentRow(link.studentId, allowMissing: true);
        if (s == null) continue;
        final similar = s.firstName.toLowerCase() == first || (last.isNotEmpty && (s.lastName ?? '').toLowerCase() == last);
        if (similar && first.isNotEmpty) found.putIfAbsent(s.id, () => DuplicateReason.sameMobileSimilarName);
      }
    }

    found.remove(excludeId);
    final matches = <DuplicateMatch>[];
    for (final entry in found.entries) {
      final s = await _studentRow(entry.key, allowMissing: true);
      if (s == null) continue;
      matches.add(DuplicateMatch(studentId: s.id, displayCode: s.displayCode, fullName: _fullName(s), reason: entry.value));
    }
    return matches;
  }

  // ============================================================== writing

  Future<String> create(StudentDraft draft, {List<ExtraFieldDefinition> extraFields = const []}) {
    return db.transaction(() async {
      await _validate(draft, extraFields: extraFields);
      final ts = now();
      final id = Uuid7.generate(ts);
      final code = await _nextCode();
      await db.into(db.students).insert(StudentsCompanion.insert(
            id: id,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            displayCode: code,
            firstName: draft.firstName.trim(),
          ));
      await _writeStudentFields(id, draft, rowVersion: 1);
      await _saveGuardians(id, draft.guardians);
      await _saveIdentifiers(id, draft.identifiers);
      if (draft.divisionId != null) {
        await _placeInDivision(id, draft.divisionId!, draft.rollNumber, startDate: draft.admissionDate);
      }
      await _refreshSearchText(id);
      await changes.record(
        table: 'students',
        rowId: id,
        operation: 'insert',
        after: {'display_code': code, ..._auditFields(draft)},
      );
      return id;
    });
  }

  Future<void> update(String studentId, StudentDraft draft, {List<ExtraFieldDefinition> extraFields = const []}) {
    return db.transaction(() async {
      final row = await _studentRow(studentId);
      final before = (await load(studentId))!.draft;
      await _validate(draft, excludeId: studentId, extraFields: extraFields);
      await _writeStudentFields(studentId, draft, rowVersion: row!.rowVersion + 1);
      await _saveGuardians(studentId, draft.guardians);
      await _saveIdentifiers(studentId, draft.identifiers);
      await _updatePlacement(studentId, draft.divisionId, draft.rollNumber);
      await _refreshSearchText(studentId);
      await changes.record(
        table: 'students',
        rowId: studentId,
        operation: 'update',
        before: _auditFields(before),
        after: _auditFields(draft),
      );
    });
  }

  /// The student stays in history; their current enrollment ends.
  Future<void> markLeft(String studentId, {required DateTime date, required String reason}) {
    return db.transaction(() async {
      final row = await _studentRow(studentId);
      final ts = now();
      await (db.update(db.students)..where((t) => t.id.equals(studentId))).write(StudentsCompanion(
        status: Value(StudentStatus.left.name),
        leavingDate: Value(_dateOnly(date)),
        leavingReason: Value(_opt(reason)),
        updatedAt: Value(ts),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(row!.rowVersion + 1),
      ));
      final active = await _activeEnrollment(studentId);
      if (active != null) await _endEnrollment(active, EnrollmentStatus.left, date);
      await changes.record(
        table: 'students',
        rowId: studentId,
        operation: 'update',
        before: {'status': row.status},
        after: {'status': StudentStatus.left.name, 'leaving_date': _iso(date), 'leaving_reason': _opt(reason)},
      );
    });
  }

  /// Moves the student to the recycle bin. Nothing is erased.
  Future<void> moveToRecycleBin(String studentId) {
    return db.transaction(() async {
      final row = await _studentRow(studentId);
      await (db.update(db.students)..where((t) => t.id.equals(studentId))).write(StudentsCompanion(
        deletedAt: Value(now()),
        updatedAt: Value(now()),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(row!.rowVersion + 1),
      ));
      await changes.record(table: 'students', rowId: studentId, operation: 'delete', before: {'deleted': false}, after: {'deleted': true});
    });
  }

  /// Moves several students to the recycle bin at once. Returns how many.
  Future<int> moveManyToRecycleBin(Iterable<String> studentIds) {
    return db.transaction(() async {
      var n = 0;
      for (final id in studentIds.toSet()) {
        await moveToRecycleBin(id);
        n++;
      }
      return n;
    });
  }

  /// Marks several students as left on the same date and reason.
  Future<int> markManyLeft(Iterable<String> studentIds, {required DateTime date, required String reason}) {
    return db.transaction(() async {
      var n = 0;
      for (final id in studentIds.toSet()) {
        await markLeft(id, date: date, reason: reason);
        n++;
      }
      return n;
    });
  }

  Future<void> restore(String studentId) {
    return db.transaction(() async {
      final row = await (db.select(db.students)
            ..where((t) => t.id.equals(studentId) & t.organizationId.equals(orgId)))
          .getSingleOrNull();
      if (row == null) throw const StudentValidationException(StudentIssue.notFound);
      await (db.update(db.students)..where((t) => t.id.equals(studentId))).write(StudentsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(now()),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(row.rowVersion + 1),
      ));
      await changes.record(table: 'students', rowId: studentId, operation: 'restore', before: {'deleted': true}, after: {'deleted': false});
    });
  }

  /// Students deleted within the last [recycleBinDays] days, newest first.
  Future<List<StudentListItem>> listRecycleBin() async {
    final since = now().subtract(const Duration(days: recycleBinDays));
    final rows = await (db.select(db.students)
          ..where((t) =>
              t.organizationId.equals(orgId) & t.deletedAt.isNotNull() & t.deletedAt.isBiggerOrEqualValue(since))
          ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
        .get();
    return [
      for (final r in rows)
        StudentListItem(id: r.id, displayCode: r.displayCode, fullName: _fullName(r), status: _status(r.status)),
    ];
  }

  /// Returns the full Aadhaar number and records who looked at it.
  Future<String?> revealAadhaar(String studentId) async {
    final row = (await _identifierRows(studentId)).where((i) => i.idType == IdentifierType.aadhaar.code).firstOrNull;
    if (row == null) return null;
    final value = await cipher.decrypt(row.idValue);
    await changes.record(
      table: 'student_identifiers',
      rowId: row.id,
      operation: 'reveal',
      after: {'id_type': IdentifierType.aadhaar.code, 'student_id': studentId},
    );
    return Aadhaar.format(value);
  }

  /// Number of students actively placed in a division (used to refuse deleting it).
  Future<int> activeCountInDivision(String divisionId) async {
    final enrollments = await (db.select(db.enrollments)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.divisionId.equals(divisionId) &
              t.status.equals(EnrollmentStatus.active.name) &
              t.deletedAt.isNull()))
        .get();
    var count = 0;
    for (final e in enrollments) {
      if (await _studentRow(e.studentId, allowMissing: true) != null) count++;
    }
    return count;
  }

  // ======================================================= import support

  /// Everything an import needs to check rows against what is already saved.
  Future<({
    Map<String, Map<String, String>> identifierOwners,
    Map<String, String> aadhaarOwners,
    Set<String> nameDob,
    Map<String, Map<int, String>> rollsByDivision,
  })> importIndex() async {
    final students = await (db.select(db.students)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull()))
        .get();
    final live = {for (final s in students) s.id};
    final identifiers = await (db.select(db.studentIdentifiers)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull()))
        .get();
    final owners = <String, Map<String, String>>{};
    final aadhaar = <String, String>{};
    for (final i in identifiers.where((i) => live.contains(i.studentId))) {
      if (i.idType == IdentifierType.aadhaar.code) {
        if (i.fingerprint != null) aadhaar[i.fingerprint!] = i.studentId;
      } else {
        (owners[i.idType] ??= {})[i.idValue.trim().toLowerCase()] = i.studentId;
      }
    }
    final enrollments = await (db.select(db.enrollments)
          ..where((t) =>
              t.organizationId.equals(orgId) & t.status.equals(EnrollmentStatus.active.name) & t.deletedAt.isNull()))
        .get();
    final rolls = <String, Map<int, String>>{};
    for (final e in enrollments.where((e) => live.contains(e.studentId) && e.rollNumber != null)) {
      (rolls[e.divisionId] ??= {})[e.rollNumber!] = e.studentId;
    }
    return (
      identifierOwners: owners,
      aadhaarOwners: aadhaar,
      nameDob: {
        for (final s in students)
          if (s.dateOfBirth != null) '${_fullName(s).toLowerCase()}|${_iso(s.dateOfBirth!)}',
      },
      rollsByDivision: rolls,
    );
  }

  /// Fills only the fields that are empty on the saved student.
  /// Returns true if anything changed. Never overwrites existing data.
  Future<bool> fillEmptyFields(String studentId, StudentDraft incoming,
      {List<ExtraFieldDefinition> extraFields = const []}) async {
    final detail = await load(studentId);
    if (detail == null) return false;
    final d = detail.draft;
    var changed = false;
    String take(String current, String next) {
      if (current.trim().isEmpty && next.trim().isNotEmpty) {
        changed = true;
        return next;
      }
      return current;
    }

    T? takeNullable<T>(T? current, T? next) {
      if (current == null && next != null) {
        changed = true;
        return next;
      }
      return current;
    }

    d.middleName = take(d.middleName, incoming.middleName);
    d.lastName = take(d.lastName, incoming.lastName);
    d.altName = take(d.altName, incoming.altName);
    d.gender = takeNullable(d.gender, incoming.gender);
    d.dateOfBirth = takeNullable(d.dateOfBirth, incoming.dateOfBirth);
    d.placeOfBirth = take(d.placeOfBirth, incoming.placeOfBirth);
    d.nationality = take(d.nationality, incoming.nationality);
    d.motherTongue = take(d.motherTongue, incoming.motherTongue);
    d.category = takeNullable(d.category, incoming.category);
    d.caste = take(d.caste, incoming.caste);
    d.subCaste = take(d.subCaste, incoming.subCaste);
    d.bloodGroup = takeNullable(d.bloodGroup, incoming.bloodGroup);
    d.heightCm = takeNullable(d.heightCm, incoming.heightCm);
    d.weightKg = takeNullable(d.weightKg, incoming.weightKg);
    d.measuredOn = takeNullable(d.measuredOn, incoming.measuredOn);
    d.address = take(d.address, incoming.address);
    d.admissionDate = takeNullable(d.admissionDate, incoming.admissionDate);
    d.previousSchool = take(d.previousSchool, incoming.previousSchool);
    if (d.guardians.isEmpty && incoming.guardians.isNotEmpty) {
      d.guardians = incoming.guardians;
      changed = true;
    }
    for (final e in incoming.identifiers.entries) {
      final has = e.key == IdentifierType.aadhaar
          ? detail.identifier(IdentifierType.aadhaar) != null
          : (d.identifiers[e.key] ?? '').isNotEmpty;
      if (!has && e.value.isNotEmpty) {
        d.identifiers[e.key] = e.value;
        changed = true;
      }
    }
    if (detail.activeEnrollment == null && incoming.divisionId != null) {
      d.divisionId = incoming.divisionId;
      d.rollNumber = incoming.rollNumber;
      changed = true;
    }
    for (final e in incoming.extra.entries) {
      if ((d.extra[e.key] ?? '').isEmpty && e.value.isNotEmpty) {
        d.extra[e.key] = e.value;
        changed = true;
      }
    }
    if (changed) await update(studentId, d, extraFields: extraFields);
    return changed;
  }

  /// Sets or clears the photo; the old file name is returned for undo.
  Future<String?> setPhoto(String studentId, String? fileName) {
    return db.transaction(() async {
      final row = await _studentRow(studentId);
      final previous = row!.photoFileName;
      await (db.update(db.students)..where((t) => t.id.equals(studentId))).write(StudentsCompanion(
        photoFileName: Value(fileName),
        updatedAt: Value(now()),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(row.rowVersion + 1),
      ));
      await changes.record(
        table: 'students',
        rowId: studentId,
        operation: 'update',
        before: {'photo_file_name': previous},
        after: {'photo_file_name': fileName},
      );
      return previous;
    });
  }

  /// Keys photos can be matched on, for every student not deleted.
  Future<List<StudentKeys>> matchingKeys(String? academicYearId) async {
    final students = await (db.select(db.students)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull()))
        .get();
    final identifiers = await (db.select(db.studentIdentifiers)
          ..where((t) =>
              t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.idType.equals(IdentifierType.aadhaar.code).not()))
        .get();
    final byStudent = <String, Map<String, String>>{};
    for (final i in identifiers) {
      (byStudent[i.studentId] ??= {})[i.idType] = i.idValue;
    }
    final placements = <String, EnrollmentRow>{};
    if (academicYearId != null) {
      final rows = await (db.select(db.enrollments)
            ..where((t) =>
                t.organizationId.equals(orgId) &
                t.academicYearId.equals(academicYearId) &
                t.status.equals(EnrollmentStatus.active.name) &
                t.deletedAt.isNull()))
          .get();
      for (final e in rows) {
        placements[e.studentId] = e;
      }
    }
    return [
      for (final s in students)
        StudentKeys(
          id: s.id,
          fullName: _fullName(s),
          displayCode: s.displayCode,
          identifiers: byStudent[s.id] ?? const {},
          divisionId: placements[s.id]?.divisionId,
          rollNumber: placements[s.id]?.rollNumber,
          hasPhoto: s.photoFileName != null,
        ),
    ];
  }

  /// Rows for an Excel or CSV export of the students list.
  Future<List<List<String>>> exportRows(List<StudentListItem> items, Map<String, String> divisionLabels) async {
    final ids = items.map((i) => i.id).toSet();
    final identifiers = await (db.select(db.studentIdentifiers)
          ..where((t) =>
              t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.idType.equals(IdentifierType.aadhaar.code).not()))
        .get();
    final byStudent = <String, Map<String, String>>{};
    for (final i in identifiers.where((i) => ids.contains(i.studentId))) {
      (byStudent[i.studentId] ??= {})[i.idType] = i.idValue;
    }
    final students = {
      for (final s in await (db.select(db.students)..where((t) => t.organizationId.equals(orgId))).get())
        s.id: s,
    };
    String date(DateTime? d) =>
        d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return [
      for (final item in items)
        [
          item.displayCode,
          students[item.id]?.firstName ?? '',
          students[item.id]?.middleName ?? '',
          students[item.id]?.lastName ?? '',
          divisionLabels[item.divisionId] ?? '',
          item.rollNumber?.toString() ?? '',
          students[item.id]?.gender ?? '',
          date(students[item.id]?.dateOfBirth),
          byStudent[item.id]?[IdentifierType.grNumber.code] ?? '',
          byStudent[item.id]?[IdentifierType.pen.code] ?? '',
          byStudent[item.id]?[IdentifierType.apaar.code] ?? '',
          byStudent[item.id]?[IdentifierType.saralId.code] ?? '',
          item.primaryMobile ?? '',
          students[item.id]?.category ?? '',
          students[item.id]?.bloodGroup ?? '',
          item.status.name,
        ],
    ];
  }

  // ============================================================== helpers

  Future<void> _validate(StudentDraft draft, {String? excludeId, required List<ExtraFieldDefinition> extraFields}) async {
    if (draft.firstName.trim().isEmpty) throw const StudentValidationException(StudentIssue.nameRequired);
    for (final g in draft.guardians.where((g) => !g.isEmpty)) {
      for (final m in [g.mobile, g.altMobile]) {
        if (m.trim().isNotEmpty && !MobileNumber.isValid(m)) {
          throw StudentValidationException(StudentIssue.invalidMobile, m);
        }
      }
    }
    for (final entry in draft.identifiers.entries) {
      final value = entry.value.trim();
      if (value.isEmpty) continue;
      if (entry.key == IdentifierType.aadhaar && !Aadhaar.isValid(value)) {
        throw const StudentValidationException(StudentIssue.invalidAadhaar);
      }
      final owner = await _identifierOwner(entry.key, value);
      if (owner != null && owner != excludeId) {
        throw StudentValidationException(StudentIssue.duplicateIdentifier, entry.key.code);
      }
    }
    for (final field in extraFields.where((f) => f.isRequired)) {
      if ((draft.extra[field.key] ?? '').trim().isEmpty) {
        throw StudentValidationException(StudentIssue.requiredFieldMissing, field.label);
      }
    }
    if (draft.divisionId != null) {
      final division = await (db.select(db.divisions)
            ..where((t) => t.id.equals(draft.divisionId!) & t.organizationId.equals(orgId) & t.deletedAt.isNull()))
          .getSingleOrNull();
      if (division == null) throw const StudentValidationException(StudentIssue.divisionNotInActiveYear);
      final year = await (db.select(db.academicYears)..where((t) => t.id.equals(division.academicYearId))).getSingleOrNull();
      if (year == null || year.status != 'active') {
        throw const StudentValidationException(StudentIssue.divisionNotInActiveYear);
      }
      if (draft.rollNumber != null) {
        final clash = await (db.select(db.enrollments)
              ..where((t) =>
                  t.organizationId.equals(orgId) &
                  t.divisionId.equals(draft.divisionId!) &
                  t.rollNumber.equals(draft.rollNumber!) &
                  t.status.equals(EnrollmentStatus.active.name) &
                  t.deletedAt.isNull()))
            .get();
        for (final e in clash) {
          if (e.studentId != excludeId && await _studentRow(e.studentId, allowMissing: true) != null) {
            throw StudentValidationException(StudentIssue.duplicateRoll, '${draft.rollNumber}');
          }
        }
      }
    }
  }

  Future<void> _writeStudentFields(String id, StudentDraft d, {required int rowVersion}) async {
    final ts = now();
    final extra = {
      for (final e in d.extra.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    };
    await (db.update(db.students)..where((t) => t.id.equals(id))).write(StudentsCompanion(
      firstName: Value(d.firstName.trim()),
      middleName: Value(_opt(d.middleName)),
      lastName: Value(_opt(d.lastName)),
      altName: Value(_opt(d.altName)),
      gender: Value(d.gender),
      dateOfBirth: Value(d.dateOfBirth == null ? null : _dateOnly(d.dateOfBirth!)),
      placeOfBirth: Value(_opt(d.placeOfBirth)),
      nationality: Value(_opt(d.nationality)),
      motherTongue: Value(_opt(d.motherTongue)),
      category: Value(d.category),
      caste: Value(_opt(d.caste)),
      subCaste: Value(_opt(d.subCaste)),
      bloodGroup: Value(d.bloodGroup),
      heightCm: Value(d.heightCm),
      weightKg: Value(d.weightKg),
      measuredOn: Value(d.measuredOn == null ? null : _dateOnly(d.measuredOn!)),
      address: Value(_opt(d.address)),
      photoFileName: Value(d.photoFileName),
      admissionDate: Value(d.admissionDate == null ? null : _dateOnly(d.admissionDate!)),
      previousSchool: Value(_opt(d.previousSchool)),
      notes: Value(_opt(d.notes)),
      extraJson: Value(jsonEncode(extra)),
      updatedAt: Value(ts),
      updatedBy: Value(session.userId),
      deviceId: Value(session.deviceId),
      rowVersion: Value(rowVersion),
    ));
  }

  Future<void> _saveGuardians(String studentId, List<GuardianDraft> drafts) async {
    final ts = now();
    final kept = drafts.where((g) => !g.isEmpty).toList();
    if (kept.isNotEmpty && !kept.any((g) => g.isPrimary)) kept.first.isPrimary = true;
    final links = await (db.select(db.studentGuardians)
          ..where((t) => t.organizationId.equals(orgId) & t.studentId.equals(studentId) & t.deletedAt.isNull()))
        .get();

    final keptIds = <String>{};
    for (final g in kept) {
      final values = GuardiansCompanion(
        name: Value(g.name.trim()),
        relation: Value(g.relation),
        mobile: Value(g.mobile.trim().isEmpty ? null : MobileNumber.normalize(g.mobile)),
        altMobile: Value(g.altMobile.trim().isEmpty ? null : MobileNumber.normalize(g.altMobile)),
        email: Value(_opt(g.email)),
        occupation: Value(_opt(g.occupation)),
        updatedAt: Value(ts),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
      );
      String guardianId;
      if (g.id != null) {
        guardianId = g.id!;
        await (db.update(db.guardians)..where((t) => t.id.equals(guardianId) & t.organizationId.equals(orgId)))
            .write(values);
      } else {
        guardianId = Uuid7.generate(ts);
        await db.into(db.guardians).insert(values.copyWith(
              id: Value(guardianId),
              organizationId: Value(orgId),
              createdAt: Value(ts),
              createdBy: Value(session.userId),
            ));
        g.id = guardianId;
      }
      keptIds.add(guardianId);
      final link = links.where((l) => l.guardianId == guardianId).firstOrNull;
      if (link == null) {
        await db.into(db.studentGuardians).insert(StudentGuardiansCompanion.insert(
              id: Uuid7.generate(ts),
              organizationId: orgId,
              createdAt: ts,
              updatedAt: ts,
              createdBy: Value(session.userId),
              updatedBy: Value(session.userId),
              deviceId: session.deviceId,
              studentId: studentId,
              guardianId: guardianId,
              isPrimary: Value(g.isPrimary),
            ));
      } else if (link.isPrimary != g.isPrimary) {
        await (db.update(db.studentGuardians)..where((t) => t.id.equals(link.id))).write(StudentGuardiansCompanion(
          isPrimary: Value(g.isPrimary),
          updatedAt: Value(ts),
          rowVersion: Value(link.rowVersion + 1),
        ));
      }
    }
    for (final link in links.where((l) => !keptIds.contains(l.guardianId))) {
      await (db.update(db.studentGuardians)..where((t) => t.id.equals(link.id)))
          .write(StudentGuardiansCompanion(deletedAt: Value(ts), updatedAt: Value(ts)));
    }
  }

  /// [values] holds the identifiers shown in the form. An empty value removes
  /// that identifier. Aadhaar is only touched when present in [values].
  Future<void> _saveIdentifiers(String studentId, Map<IdentifierType, String> values) async {
    final ts = now();
    final existing = await _identifierRows(studentId);
    for (final type in IdentifierType.values) {
      if (!values.containsKey(type)) continue;
      final raw = values[type]!.trim();
      final current = existing.where((i) => i.idType == type.code).firstOrNull;
      if (raw.isEmpty) {
        if (current != null) {
          await (db.update(db.studentIdentifiers)..where((t) => t.id.equals(current.id)))
              .write(StudentIdentifiersCompanion(deletedAt: Value(ts), updatedAt: Value(ts)));
          await changes.record(
            table: 'student_identifiers',
            rowId: current.id,
            operation: 'delete',
            before: {'id_type': type.code},
            after: {'id_type': type.code, 'deleted': true},
          );
        }
        continue;
      }
      final String stored;
      String? lastFour;
      String? fingerprint;
      if (type == IdentifierType.aadhaar) {
        final digits = Aadhaar.normalize(raw);
        stored = await cipher.encrypt(digits);
        lastFour = digits.substring(8);
        fingerprint = await cipher.fingerprint(digits);
        if (current != null && current.fingerprint == fingerprint) continue;
      } else {
        stored = raw;
        if (current != null && current.idValue == stored) continue;
      }
      // The audit log never holds the Aadhaar number itself.
      final auditValue = type == IdentifierType.aadhaar ? Aadhaar.mask(lastFour!) : stored;
      if (current == null) {
        final id = Uuid7.generate(ts);
        await db.into(db.studentIdentifiers).insert(StudentIdentifiersCompanion.insert(
              id: id,
              organizationId: orgId,
              createdAt: ts,
              updatedAt: ts,
              createdBy: Value(session.userId),
              updatedBy: Value(session.userId),
              deviceId: session.deviceId,
              studentId: studentId,
              idType: type.code,
              idValue: stored,
              lastFour: Value(lastFour),
              fingerprint: Value(fingerprint),
            ));
        await changes.record(
          table: 'student_identifiers',
          rowId: id,
          operation: 'insert',
          after: {'id_type': type.code, 'value': auditValue},
        );
      } else {
        await (db.update(db.studentIdentifiers)..where((t) => t.id.equals(current.id))).write(StudentIdentifiersCompanion(
          idValue: Value(stored),
          lastFour: Value(lastFour),
          fingerprint: Value(fingerprint),
          updatedAt: Value(ts),
          updatedBy: Value(session.userId),
          deviceId: Value(session.deviceId),
          rowVersion: Value(current.rowVersion + 1),
        ));
        final oldAudit = type == IdentifierType.aadhaar ? Aadhaar.mask(current.lastFour ?? '????') : current.idValue;
        await changes.record(
          table: 'student_identifiers',
          rowId: current.id,
          operation: 'update',
          before: {'id_type': type.code, 'value': oldAudit},
          after: {'id_type': type.code, 'value': auditValue},
        );
      }
    }
  }

  Future<void> _placeInDivision(String studentId, String divisionId, int? roll, {DateTime? startDate}) async {
    final division = await (db.select(db.divisions)..where((t) => t.id.equals(divisionId))).getSingle();
    final ts = now();
    final id = Uuid7.generate(ts);
    final start = _dateOnly(startDate ?? ts);
    await db.into(db.enrollments).insert(EnrollmentsCompanion.insert(
          id: id,
          organizationId: orgId,
          createdAt: ts,
          updatedAt: ts,
          createdBy: Value(session.userId),
          updatedBy: Value(session.userId),
          deviceId: session.deviceId,
          studentId: studentId,
          academicYearId: division.academicYearId,
          divisionId: divisionId,
          rollNumber: Value(roll),
          startDate: start,
          status: EnrollmentStatus.active.name,
        ));
    await changes.record(
      table: 'enrollments',
      rowId: id,
      operation: 'insert',
      after: {'student_id': studentId, 'division_id': divisionId, 'roll_number': roll, 'start_date': _iso(start)},
    );
  }

  Future<void> _updatePlacement(String studentId, String? divisionId, int? roll) async {
    if (divisionId == null) return;
    final active = await _activeEnrollment(studentId);
    if (active == null) {
      await _placeInDivision(studentId, divisionId, roll);
      return;
    }
    if (active.divisionId != divisionId) {
      // A move closes one enrollment and opens another, so history stays exact.
      await _endEnrollment(active, EnrollmentStatus.transferred, now());
      await _placeInDivision(studentId, divisionId, roll);
      return;
    }
    if (active.rollNumber != roll) {
      await (db.update(db.enrollments)..where((t) => t.id.equals(active.id))).write(EnrollmentsCompanion(
        rollNumber: Value(roll),
        updatedAt: Value(now()),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(active.rowVersion + 1),
      ));
      await changes.record(
        table: 'enrollments',
        rowId: active.id,
        operation: 'update',
        before: {'roll_number': active.rollNumber},
        after: {'roll_number': roll},
      );
    }
  }

  Future<void> _endEnrollment(EnrollmentRow e, EnrollmentStatus status, DateTime date) async {
    await (db.update(db.enrollments)..where((t) => t.id.equals(e.id))).write(EnrollmentsCompanion(
      status: Value(status.name),
      endDate: Value(_dateOnly(date)),
      updatedAt: Value(now()),
      updatedBy: Value(session.userId),
      deviceId: Value(session.deviceId),
      rowVersion: Value(e.rowVersion + 1),
    ));
    await changes.record(
      table: 'enrollments',
      rowId: e.id,
      operation: 'update',
      before: {'status': e.status},
      after: {'status': status.name, 'end_date': _iso(date)},
    );
  }

  Future<EnrollmentRow?> _activeEnrollment(String studentId) {
    return (db.select(db.enrollments)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.studentId.equals(studentId) &
              t.status.equals(EnrollmentStatus.active.name) &
              t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<void> _refreshSearchText(String studentId) async {
    final s = await _studentRow(studentId);
    final ids = (await _identifierRows(studentId)).where((i) => i.idType != IdentifierType.aadhaar.code);
    final links = await (db.select(db.studentGuardians)
          ..where((t) => t.organizationId.equals(orgId) & t.studentId.equals(studentId) & t.deletedAt.isNull()))
        .get();
    final guardians = links.isEmpty
        ? <GuardianRow>[]
        : await (db.select(db.guardians)..where((t) => t.id.isIn(links.map((l) => l.guardianId)))).get();
    final text = [
      s!.firstName,
      s.middleName,
      s.lastName,
      s.altName,
      s.displayCode,
      for (final i in ids) i.idValue,
      for (final g in guardians) ...[g.name, g.mobile, g.altMobile],
    ].whereType<String>().join(' ').toLowerCase();
    await (db.update(db.students)..where((t) => t.id.equals(studentId))).write(StudentsCompanion(searchText: Value(text)));
  }

  Future<String> _nextCode() async {
    final seq = await (db.select(db.sequences)
          ..where((t) => t.organizationId.equals(orgId) & t.name.equals(_codeSequence)))
        .getSingleOrNull();
    int value;
    if (seq == null) {
      final count = db.students.id.count();
      final existing = await (db.selectOnly(db.students)
            ..addColumns([count])
            ..where(db.students.organizationId.equals(orgId)))
          .getSingle();
      value = (existing.read(count) ?? 0) + 1;
      await db.into(db.sequences).insert(
            SequencesCompanion.insert(organizationId: orgId, name: _codeSequence, nextValue: value + 1),
          );
    } else {
      value = seq.nextValue;
      await (db.update(db.sequences)..where((t) => t.organizationId.equals(orgId) & t.name.equals(_codeSequence)))
          .write(SequencesCompanion(nextValue: Value(value + 1)));
    }
    return 'STU-${value.toString().padLeft(6, '0')}';
  }

  Future<String?> _identifierOwner(IdentifierType type, String value) async {
    final rows = await (db.select(db.studentIdentifiers)
          ..where((t) => t.organizationId.equals(orgId) & t.idType.equals(type.code) & t.deletedAt.isNull()))
        .get();
    if (type == IdentifierType.aadhaar) {
      final fp = await cipher.fingerprint(Aadhaar.normalize(value));
      for (final r in rows) {
        if (r.fingerprint == fp && await _studentRow(r.studentId, allowMissing: true) != null) return r.studentId;
      }
      return null;
    }
    final wanted = value.trim().toLowerCase();
    for (final r in rows) {
      if (r.idValue.trim().toLowerCase() == wanted && await _studentRow(r.studentId, allowMissing: true) != null) {
        return r.studentId;
      }
    }
    return null;
  }

  Future<List<StudentIdentifierRow>> _identifierRows(String studentId) {
    return (db.select(db.studentIdentifiers)
          ..where((t) => t.organizationId.equals(orgId) & t.studentId.equals(studentId) & t.deletedAt.isNull()))
        .get();
  }

  Future<StudentRow?> _studentRow(String id, {bool allowMissing = false}) async {
    final row = await (db.select(db.students)
          ..where((t) => t.id.equals(id) & t.organizationId.equals(orgId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null && !allowMissing) throw const StudentValidationException(StudentIssue.notFound);
    return row;
  }

  Future<Map<String, String>> _primaryMobiles() async {
    final links = await (db.select(db.studentGuardians)
          ..where((t) => t.organizationId.equals(orgId) & t.isPrimary.equals(true) & t.deletedAt.isNull()))
        .get();
    if (links.isEmpty) return {};
    final guardians = await (db.select(db.guardians)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull()))
        .get();
    final mobileById = {for (final g in guardians) g.id: g.mobile};
    return {
      for (final l in links)
        if (mobileById[l.guardianId] != null) l.studentId: mobileById[l.guardianId]!,
    };
  }

  static Map<String, Object?> _auditFields(StudentDraft d) => {
        'first_name': d.firstName.trim(),
        'middle_name': _opt(d.middleName),
        'last_name': _opt(d.lastName),
        'alt_name': _opt(d.altName),
        'gender': d.gender,
        'date_of_birth': d.dateOfBirth == null ? null : _iso(d.dateOfBirth!),
        'place_of_birth': _opt(d.placeOfBirth),
        'nationality': _opt(d.nationality),
        'mother_tongue': _opt(d.motherTongue),
        'category': d.category,
        'caste': _opt(d.caste),
        'sub_caste': _opt(d.subCaste),
        'blood_group': d.bloodGroup,
        'height_cm': d.heightCm,
        'weight_kg': d.weightKg,
        'address': _opt(d.address),
        'admission_date': d.admissionDate == null ? null : _iso(d.admissionDate!),
        'previous_school': _opt(d.previousSchool),
        'division_id': d.divisionId,
        'roll_number': d.rollNumber,
      };

  static Map<String, String> _decodeExtra(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, '$v'));
    } catch (_) {
      return {};
    }
  }

  static String _fullName(StudentRow r) =>
      [r.firstName, r.middleName, r.lastName].whereType<String>().where((s) => s.isNotEmpty).join(' ');

  static StudentStatus _status(String s) =>
      StudentStatus.values.firstWhere((v) => v.name == s, orElse: () => StudentStatus.active);

  static String? _opt(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

  static DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static String _iso(DateTime d) => _dateOnly(d).toIso8601String().substring(0, 10);
}
