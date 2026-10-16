import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/org_scoped_repository.dart';
import '../../../core/ids/uuid7.dart';
import '../../../platform/data/app_settings_repository.dart';
import '../domain/attendance_models.dart';

/// Daily attendance: who belongs on a sheet, saving marks, the edit window,
/// holidays, and percentages. Every rule lives here, whatever screen calls it.
class AttendanceRepository extends OrgScopedRepository {
  AttendanceRepository(super.db, super.session, this.settings, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppSettingsRepository settings;
  final DateTime Function() _clock;

  static const editDaysKey = 'attendance.edit_days';
  static const weeklyOffKey = 'attendance.weekly_off';
  static const defaultEditDays = 7;
  static const defaultWeeklyOff = [DateTime.sunday];

  // ================================================================ settings

  Future<int> editDays() async => int.tryParse(await settings.getValue(editDaysKey) ?? '') ?? defaultEditDays;

  Future<void> setEditDays(int days) => settings.setValue(editDaysKey, '$days');

  Future<List<int>> weeklyOff() async {
    final raw = await settings.getValue(weeklyOffKey);
    if (raw == null) return defaultWeeklyOff;
    return (jsonDecode(raw) as List<dynamic>).map((e) => e as int).toList();
  }

  Future<void> setWeeklyOff(List<int> weekdays) => settings.setValue(weeklyOffKey, jsonEncode(weekdays));

  // =================================================================== codes

  /// The institution's codes; the defaults P, A, L are added the first time.
  Future<List<AttendanceCode>> codes() async {
    var rows = await _codeRows();
    if (rows.isEmpty) {
      await db.transaction(() async {
        await _insertCode('P', 'Present', 0xFF2E7D32, CountsAs.present, 10);
        await _insertCode('A', 'Absent', 0xFFC62828, CountsAs.absent, 20);
        await _insertCode('L', 'Leave', 0xFFB26A00, CountsAs.absent, 30);
      });
      rows = await _codeRows();
    }
    return rows.map(_code).toList();
  }

  Future<void> addCode({required String code, required String label, required int colorValue, required CountsAs countsAs}) {
    return db.transaction(() async {
      final clean = code.trim().toUpperCase();
      if (clean.isEmpty || clean.length > 3) throw const AttendanceException(AttendanceIssue.emptyCode);
      final existing = await codes();
      if (existing.any((c) => c.code == clean)) throw const AttendanceException(AttendanceIssue.duplicateCode);
      final order = existing.isEmpty ? 10 : existing.last.displayOrder + 10;
      await _insertCode(clean, label.trim().isEmpty ? clean : label.trim(), colorValue, countsAs, order);
    });
  }

  Future<void> updateCode(String id, {required String label, required int colorValue, required CountsAs countsAs}) {
    return db.transaction(() async {
      final row = await (db.select(db.attendanceCodes)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
          .getSingle();
      await (db.update(db.attendanceCodes)..where((t) => t.id.equals(id))).write(AttendanceCodesCompanion(
        label: Value(label.trim().isEmpty ? row.code : label.trim()),
        colorValue: Value(colorValue),
        countsAs: Value(countsAs.name),
        updatedAt: Value(now()),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(row.rowVersion + 1),
      ));
      await changes.record(
        table: 'attendance_codes',
        rowId: id,
        operation: 'update',
        before: {'label': row.label, 'color': row.colorValue, 'counts_as': row.countsAs},
        after: {'label': label.trim(), 'color': colorValue, 'counts_as': countsAs.name},
      );
    });
  }

  /// Only codes never used on any sheet can be deleted.
  Future<void> deleteCode(String id) {
    return db.transaction(() async {
      final row = await (db.select(db.attendanceCodes)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
          .getSingle();
      final used = await (db.select(db.attendanceRecords)
            ..where((t) => t.organizationId.equals(orgId) & t.code.equals(row.code) & t.deletedAt.isNull())
            ..limit(1))
          .get();
      if (used.isNotEmpty) throw const AttendanceException(AttendanceIssue.codeInUse);
      await (db.update(db.attendanceCodes)..where((t) => t.id.equals(id)))
          .write(AttendanceCodesCompanion(deletedAt: Value(now()), updatedAt: Value(now())));
      await changes.record(table: 'attendance_codes', rowId: id, operation: 'delete', after: {'code': row.code});
    });
  }

  // ================================================================ calendar

  Future<List<CalendarEntry>> calendar() async {
    final rows = await (db.select(db.calendarDays)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();
    return [
      for (final r in rows)
        CalendarEntry(id: r.id, date: r.date, kind: r.dayType == 'exam' ? DayKind.exam : DayKind.holiday, note: r.note),
    ];
  }

  /// Adds or replaces the entry for that date.
  Future<void> setCalendarDay(DateTime date, DayKind kind, String note) {
    return db.transaction(() async {
      final d = _day(date);
      final existing = await (db.select(db.calendarDays)
            ..where((t) => t.organizationId.equals(orgId) & t.date.equals(d) & t.deletedAt.isNull()))
          .get();
      for (final e in existing) {
        await (db.update(db.calendarDays)..where((t) => t.id.equals(e.id)))
            .write(CalendarDaysCompanion(deletedAt: Value(now()), updatedAt: Value(now())));
      }
      final ts = now();
      final id = Uuid7.generate(ts);
      await db.into(db.calendarDays).insert(CalendarDaysCompanion.insert(
            id: id,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            date: d,
            dayType: kind == DayKind.exam ? 'exam' : 'holiday',
            note: Value(note.trim()),
          ));
      await changes.record(
        table: 'calendar_days',
        rowId: id,
        operation: 'insert',
        after: {'date': _iso(d), 'type': kind.name, 'note': note.trim()},
      );
    });
  }

  Future<void> removeCalendarDay(String id) {
    return db.transaction(() async {
      await (db.update(db.calendarDays)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
          .write(CalendarDaysCompanion(deletedAt: Value(now()), updatedAt: Value(now())));
      await changes.record(table: 'calendar_days', rowId: id, operation: 'delete', after: {'deleted': true});
    });
  }

  Future<DayInfo> dayInfo(DateTime date) async {
    final d = _day(date);
    final today = _day(_clock());
    final entry = await (db.select(db.calendarDays)
          ..where((t) => t.organizationId.equals(orgId) & t.date.equals(d) & t.deletedAt.isNull()))
        .getSingleOrNull();
    final off = await weeklyOff();
    final kind = entry != null
        ? (entry.dayType == 'exam' ? DayKind.exam : DayKind.holiday)
        : (off.contains(d.weekday) ? DayKind.weeklyOff : DayKind.working);
    final window = await editDays();
    return DayInfo(
      date: d,
      kind: kind,
      note: entry?.note,
      isFuture: d.isAfter(today),
      isLocked: today.difference(d).inDays > window,
    );
  }

  // ================================================================== sheets

  /// Students in the division on that date: joined on or before it and not
  /// left before it. Ordered by roll number, then name.
  Future<List<RosterEntry>> roster(String divisionId, DateTime date) async {
    final d = _day(date);
    final enrollments = await (db.select(db.enrollments)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.divisionId.equals(divisionId) &
              t.deletedAt.isNull() &
              t.startDate.isSmallerOrEqualValue(d) &
              (t.endDate.isNull() | t.endDate.isBiggerThanValue(d))))
        .get();
    if (enrollments.isEmpty) return [];
    final students = await (db.select(db.students)
          ..where((t) =>
              t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.id.isIn(enrollments.map((e) => e.studentId))))
        .get();
    final byId = {for (final s in students) s.id: s};
    final list = [
      for (final e in enrollments)
        if (byId[e.studentId] case final s?)
          RosterEntry(
            studentId: s.id,
            enrollmentId: e.id,
            fullName: [s.firstName, s.middleName, s.lastName].whereType<String>().where((x) => x.isNotEmpty).join(' '),
            displayCode: s.displayCode,
            rollNumber: e.rollNumber,
            photoFileName: s.photoFileName,
          ),
    ];
    list.sort((a, b) {
      if (a.rollNumber != null && b.rollNumber != null) return a.rollNumber!.compareTo(b.rollNumber!);
      if (a.rollNumber != null) return -1;
      if (b.rollNumber != null) return 1;
      return a.fullName.compareTo(b.fullName);
    });
    return list;
  }

  Future<AttendanceSheet> sheet(String divisionId, DateTime date) async {
    final d = _day(date);
    final info = await dayInfo(d);
    final roster = await this.roster(divisionId, d);
    final session = await _sessionRow(divisionId, d);
    final marks = <String, String>{};
    if (session != null) {
      final records = await (db.select(db.attendanceRecords)
            ..where((t) => t.sessionId.equals(session.id) & t.deletedAt.isNull()))
          .get();
      for (final r in records) {
        marks[r.studentId] = r.code;
      }
    }
    return AttendanceSheet(
      day: info,
      roster: roster,
      marks: marks,
      sessionId: session?.id,
      savedAt: session?.updatedAt,
      savedBy: session?.updatedBy,
    );
  }

  /// Saves a division's marks for a date. Refused for future dates, days that
  /// are not working days (unless [allowNonWorkingDay]), and dates outside
  /// the edit window. Every change is recorded in the audit log.
  Future<void> save(String divisionId, DateTime date, Map<String, String> marks, {bool allowNonWorkingDay = false}) {
    return db.transaction(() async {
      final d = _day(date);
      final info = await dayInfo(d);
      if (info.isFuture) throw const AttendanceException(AttendanceIssue.futureDate);
      if (info.isLocked) throw const AttendanceException(AttendanceIssue.locked);
      if (!info.isMarkable && !allowNonWorkingDay) throw const AttendanceException(AttendanceIssue.notWorkingDay);
      final known = {for (final c in await codes()) c.code};
      for (final code in marks.values) {
        if (!known.contains(code)) throw AttendanceException(AttendanceIssue.unknownCode, code);
      }
      final roster = {for (final r in await this.roster(divisionId, d)) r.studentId: r};
      final ts = now();

      var sessionRow = await _sessionRow(divisionId, d);
      final isNew = sessionRow == null;
      if (sessionRow == null) {
        final division = await (db.select(db.divisions)..where((t) => t.id.equals(divisionId))).getSingle();
        final id = Uuid7.generate(ts);
        await db.into(db.attendanceSessions).insert(AttendanceSessionsCompanion.insert(
              id: id,
              organizationId: orgId,
              createdAt: ts,
              updatedAt: ts,
              createdBy: Value(session.userId),
              updatedBy: Value(session.userId),
              deviceId: session.deviceId,
              academicYearId: division.academicYearId,
              divisionId: divisionId,
              date: d,
              takenBy: Value(session.userId),
            ));
        sessionRow = await (db.select(db.attendanceSessions)..where((t) => t.id.equals(id))).getSingle();
      } else {
        await (db.update(db.attendanceSessions)..where((t) => t.id.equals(sessionRow!.id))).write(AttendanceSessionsCompanion(
          updatedAt: Value(ts),
          updatedBy: Value(session.userId),
          deviceId: Value(session.deviceId),
          rowVersion: Value(sessionRow.rowVersion + 1),
        ));
      }

      final existing = {
        for (final r in await (db.select(db.attendanceRecords)
              ..where((t) => t.sessionId.equals(sessionRow!.id) & t.deletedAt.isNull()))
            .get())
          r.studentId: r,
      };
      final changed = <String, Map<String, String?>>{};
      for (final entry in marks.entries) {
        final student = roster[entry.key];
        if (student == null) continue; // not on this sheet on this date
        final old = existing[entry.key];
        if (old == null) {
          await db.into(db.attendanceRecords).insert(AttendanceRecordsCompanion.insert(
                id: Uuid7.generate(ts),
                organizationId: orgId,
                createdAt: ts,
                updatedAt: ts,
                createdBy: Value(session.userId),
                updatedBy: Value(session.userId),
                deviceId: session.deviceId,
                sessionId: sessionRow.id,
                enrollmentId: student.enrollmentId,
                studentId: entry.key,
                code: entry.value,
              ));
          if (!isNew) changed[entry.key] = {'old': null, 'new': entry.value};
        } else if (old.code != entry.value) {
          await (db.update(db.attendanceRecords)..where((t) => t.id.equals(old.id))).write(AttendanceRecordsCompanion(
            code: Value(entry.value),
            updatedAt: Value(ts),
            updatedBy: Value(session.userId),
            deviceId: Value(session.deviceId),
            rowVersion: Value(old.rowVersion + 1),
          ));
          changed[entry.key] = {'old': old.code, 'new': entry.value};
        }
      }
      final counts = <String, int>{};
      for (final c in marks.values) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
      await changes.record(
        table: 'attendance_sessions',
        rowId: sessionRow.id,
        operation: isNew ? 'insert' : 'update',
        before: isNew ? null : {'changed_students': null},
        after: {
          'division_id': divisionId,
          'date': _iso(d),
          'counts': counts,
          if (!isNew) 'changed_students': changed,
        },
      );
    });
  }

  // ============================================================ summaries

  Future<MonthGrid> monthGrid(String divisionId, int year, int month) async {
    final first = DateTime.utc(year, month, 1);
    final last = DateTime.utc(year, month + 1, 0);
    final codeMap = {for (final c in await codes()) c.code: c};

    // Everyone on the sheet at any point in the month.
    final enrollments = await (db.select(db.enrollments)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.divisionId.equals(divisionId) &
              t.deletedAt.isNull() &
              t.startDate.isSmallerOrEqualValue(last) &
              (t.endDate.isNull() | t.endDate.isBiggerThanValue(first))))
        .get();
    final seen = <String>{};
    final students = <RosterEntry>[];
    final roster = await this.roster(divisionId, last.isAfter(_day(_clock())) ? _day(_clock()) : last);
    for (final r in roster) {
      if (seen.add(r.studentId)) students.add(r);
    }
    for (final e in enrollments) {
      if (seen.contains(e.studentId)) continue;
      final s = await (db.select(db.students)..where((t) => t.id.equals(e.studentId) & t.deletedAt.isNull()))
          .getSingleOrNull();
      if (s == null) continue;
      seen.add(s.id);
      students.add(RosterEntry(
        studentId: s.id,
        enrollmentId: e.id,
        fullName: [s.firstName, s.middleName, s.lastName].whereType<String>().where((x) => x.isNotEmpty).join(' '),
        displayCode: s.displayCode,
        rollNumber: e.rollNumber,
        photoFileName: s.photoFileName,
      ));
    }

    final sessions = await (db.select(db.attendanceSessions)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.divisionId.equals(divisionId) &
              t.deletedAt.isNull() &
              t.date.isBetweenValues(first, last)))
        .get();
    final dayOfSession = {for (final s in sessions) s.id: s.date.day};
    final marks = <String, Map<int, String>>{};
    if (sessions.isNotEmpty) {
      final records = await (db.select(db.attendanceRecords)
            ..where((t) => t.deletedAt.isNull() & t.sessionId.isIn(sessions.map((s) => s.id))))
          .get();
      for (final r in records) {
        (marks[r.studentId] ??= {})[dayOfSession[r.sessionId]!] = r.code;
      }
    }

    final totals = {for (final s in students) s.studentId: _summarise((marks[s.studentId] ?? {}).values, codeMap)};
    final off = await weeklyOff();
    final calendar = await (db.select(db.calendarDays)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.date.isBetweenValues(first, last)))
        .get();
    final kinds = <int, DayKind>{
      for (var day = 1; day <= last.day; day++)
        if (off.contains(DateTime.utc(year, month, day).weekday)) day: DayKind.weeklyOff,
    };
    for (final c in calendar) {
      kinds[c.date.day] = c.dayType == 'exam' ? DayKind.exam : DayKind.holiday;
    }
    return MonthGrid(year: year, month: month, students: students, marks: marks, totals: totals, dayKinds: kinds);
  }

  /// A student's attendance between two dates (both included).
  Future<AttendanceSummary> studentSummary(String studentId, {required DateTime from, required DateTime to}) async {
    final codeMap = {for (final c in await codes()) c.code: c};
    final rows = await _studentMarks(studentId, from, to);
    return _summarise(rows.map((r) => r.$2), codeMap);
  }

  /// One student's attendance for a period, for the profile: the summary
  /// (same rules as [studentSummary]) and the latest marked days, newest
  /// first, as (date, code).
  Future<({AttendanceSummary summary, List<(DateTime, String)> recent})> studentPeriod(
    String studentId, {
    required DateTime from,
    required DateTime to,
    int recent = 10,
  }) async {
    final codeMap = {for (final c in await codes()) c.code: c};
    final rows = await _studentMarks(studentId, from, to);
    return (
      summary: _summarise(rows.map((r) => r.$2), codeMap),
      recent: rows.reversed.take(recent).toList(),
    );
  }

  /// The student's most recent days counted as absent.
  Future<List<DateTime>> recentAbsences(String studentId, {int limit = 5}) async {
    final codeMap = {for (final c in await codes()) c.code: c};
    final rows = await _studentMarks(studentId, DateTime.utc(2000), _day(_clock()));
    return rows
        .where((r) => codeMap[r.$2]?.countsAs == CountsAs.absent)
        .map((r) => r.$1)
        .toList()
        .reversed
        .take(limit)
        .toList();
  }

  /// Present / absent counts across all divisions for one date (dashboard).
  Future<({int marked, int present, int absent})> dayTotals(DateTime date) async {
    final d = _day(date);
    final codeMap = {for (final c in await codes()) c.code: c};
    final sessions = await (db.select(db.attendanceSessions)
          ..where((t) => t.organizationId.equals(orgId) & t.date.equals(d) & t.deletedAt.isNull()))
        .get();
    if (sessions.isEmpty) return (marked: 0, present: 0, absent: 0);
    final records = await (db.select(db.attendanceRecords)
          ..where((t) => t.deletedAt.isNull() & t.sessionId.isIn(sessions.map((s) => s.id))))
        .get();
    var present = 0, absent = 0;
    for (final r in records) {
      switch (codeMap[r.code]?.countsAs) {
        case CountsAs.present:
        case CountsAs.half:
          present++;
        case CountsAs.absent:
          absent++;
        default:
          break;
      }
    }
    return (marked: records.length, present: present, absent: absent);
  }

  // ============================================================ dashboard

  /// Divisions with students on [date] whose attendance is not saved yet.
  Future<List<String>> unmarkedDivisions(DateTime date, Iterable<String> divisionIds) async {
    final d = _day(date);
    final marked = {
      for (final s in await (db.select(db.attendanceSessions)
            ..where((t) => t.organizationId.equals(orgId) & t.date.equals(d) & t.deletedAt.isNull()))
          .get())
        s.divisionId,
    };
    final out = <String>[];
    for (final id in divisionIds) {
      if (marked.contains(id)) continue;
      if ((await roster(id, d)).isNotEmpty) out.add(id);
    }
    return out;
  }

  /// Students marked with an absent-type mark on [date], with their division.
  Future<List<({String studentId, String divisionId, String code})>> absentOn(DateTime date) async {
    final d = _day(date);
    final codeMap = {for (final c in await codes()) c.code: c};
    final sessions = await (db.select(db.attendanceSessions)
          ..where((t) => t.organizationId.equals(orgId) & t.date.equals(d) & t.deletedAt.isNull()))
        .get();
    if (sessions.isEmpty) return [];
    final division = {for (final s in sessions) s.id: s.divisionId};
    final records = await (db.select(db.attendanceRecords)
          ..where((t) => t.deletedAt.isNull() & t.sessionId.isIn(sessions.map((s) => s.id))))
        .get();
    return [
      for (final r in records)
        if (codeMap[r.code]?.countsAs == CountsAs.absent)
          (studentId: r.studentId, divisionId: division[r.sessionId]!, code: r.code),
    ];
  }

  /// For each student, how many marked days in a row ending on [date] were
  /// counted as absent (0 when present on [date]). Days with no mark
  /// (holidays, weekly offs) do not break a streak.
  Future<Map<String, int>> absentStreaks(Iterable<String> studentIds, DateTime date, {int lookBackDays = 60}) async {
    final ids = studentIds.toSet();
    if (ids.isEmpty) return {};
    final codeMap = {for (final c in await codes()) c.code: c};
    final to = _day(date);
    final from = to.subtract(Duration(days: lookBackDays));
    final sessions = await (db.select(db.attendanceSessions)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.date.isBetweenValues(from, to)))
        .get();
    if (sessions.isEmpty) return {for (final id in ids) id: 0};
    final dates = {for (final s in sessions) s.id: s.date};
    final records = await (db.select(db.attendanceRecords)
          ..where((t) => t.deletedAt.isNull() & t.studentId.isIn(ids) & t.sessionId.isIn(dates.keys)))
        .get();
    final byStudent = <String, List<(DateTime, String)>>{};
    for (final r in records) {
      final d = dates[r.sessionId];
      if (d != null) (byStudent[r.studentId] ??= []).add((d, r.code));
    }
    final out = <String, int>{};
    for (final id in ids) {
      final marks = (byStudent[id] ?? [])..sort((a, b) => b.$1.compareTo(a.$1));
      var streak = 0;
      for (final m in marks) {
        final kind = codeMap[m.$2]?.countsAs;
        if (kind == CountsAs.excluded) continue;
        if (kind != CountsAs.absent) break;
        streak++;
      }
      out[id] = streak;
    }
    return out;
  }

  /// Students below [threshold]% between two dates, with at least [minDays] counted days.
  /// Lowest first.
  Future<List<({String studentId, AttendanceSummary summary})>> lowAttendance({
    required DateTime from,
    required DateTime to,
    double threshold = 75,
    int minDays = 5,
  }) async {
    final codeMap = {for (final c in await codes()) c.code: c};
    final sessions = await (db.select(db.attendanceSessions)
          ..where((t) =>
              t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.date.isBetweenValues(_day(from), _day(to))))
        .get();
    if (sessions.isEmpty) return [];
    final records = await (db.select(db.attendanceRecords)
          ..where((t) => t.deletedAt.isNull() & t.sessionId.isIn(sessions.map((s) => s.id))))
        .get();
    final byStudent = <String, List<String>>{};
    for (final r in records) {
      (byStudent[r.studentId] ??= []).add(r.code);
    }
    final out = <({String studentId, AttendanceSummary summary})>[];
    for (final e in byStudent.entries) {
      final s = _summarise(e.value, codeMap);
      final counted = s.present + s.absent;
      if (counted >= minDays && (s.percent ?? 100) < threshold) out.add((studentId: e.key, summary: s));
    }
    out.sort((a, b) => (a.summary.percent ?? 0).compareTo(b.summary.percent ?? 0));
    return out;
  }

  /// Per division between two dates: days marked, average attendance %
  /// and how many students are below [threshold].
  Future<Map<String, ({int days, double? average, int below, int students})>> divisionSummaries({
    required DateTime from,
    required DateTime to,
    double threshold = 75,
  }) async {
    final codeMap = {for (final c in await codes()) c.code: c};
    final sessions = await (db.select(db.attendanceSessions)
          ..where((t) =>
              t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.date.isBetweenValues(_day(from), _day(to))))
        .get();
    if (sessions.isEmpty) return {};
    final divisionOf = {for (final s in sessions) s.id: s.divisionId};
    final days = <String, int>{};
    for (final s in sessions) {
      days[s.divisionId] = (days[s.divisionId] ?? 0) + 1;
    }
    final records = await (db.select(db.attendanceRecords)
          ..where((t) => t.deletedAt.isNull() & t.sessionId.isIn(sessions.map((s) => s.id))))
        .get();
    final marks = <String, Map<String, List<String>>>{};
    for (final r in records) {
      ((marks[divisionOf[r.sessionId]!] ??= {})[r.studentId] ??= []).add(r.code);
    }
    return {
      for (final e in marks.entries)
        e.key: () {
          final percents = [
            for (final m in e.value.values)
              if (_summarise(m, codeMap).percent case final p?) p,
          ];
          return (
            days: days[e.key] ?? 0,
            average: percents.isEmpty ? null : percents.reduce((a, b) => a + b) / percents.length,
            below: percents.where((p) => p < threshold).length,
            students: e.value.length,
          );
        }(),
    };
  }

  // ================================================================ helpers

  Future<List<(DateTime, String)>> _studentMarks(String studentId, DateTime from, DateTime to) async {
    final records = await (db.select(db.attendanceRecords)
          ..where((t) => t.organizationId.equals(orgId) & t.studentId.equals(studentId) & t.deletedAt.isNull()))
        .get();
    if (records.isEmpty) return [];
    final sessions = await (db.select(db.attendanceSessions)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.id.isIn(records.map((r) => r.sessionId)) &
              t.date.isBetweenValues(_day(from), _day(to))))
        .get();
    final dates = {for (final s in sessions) s.id: s.date};
    final out = [
      for (final r in records)
        if (dates[r.sessionId] case final d?) (d, r.code),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  static AttendanceSummary _summarise(Iterable<String> marks, Map<String, AttendanceCode> codes) {
    var present = 0.0, absent = 0.0, excluded = 0, days = 0;
    for (final m in marks) {
      days++;
      switch (codes[m]?.countsAs ?? CountsAs.excluded) {
        case CountsAs.present:
          present += 1;
        case CountsAs.absent:
          absent += 1;
        case CountsAs.half:
          present += 0.5;
          absent += 0.5;
        case CountsAs.excluded:
          excluded++;
      }
    }
    return AttendanceSummary(present: present, absent: absent, excluded: excluded, days: days);
  }

  Future<AttendanceSessionRow?> _sessionRow(String divisionId, DateTime d) {
    return (db.select(db.attendanceSessions)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.divisionId.equals(divisionId) &
              t.date.equals(d) &
              t.period.isNull() &
              t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<List<AttendanceCodeRow>> _codeRows() {
    return (db.select(db.attendanceCodes)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.displayOrder)]))
        .get();
  }

  Future<void> _insertCode(String code, String label, int color, CountsAs countsAs, int order) async {
    final ts = now();
    final id = Uuid7.generate(ts);
    await db.into(db.attendanceCodes).insert(AttendanceCodesCompanion.insert(
          id: id,
          organizationId: orgId,
          createdAt: ts,
          updatedAt: ts,
          createdBy: Value(session.userId),
          updatedBy: Value(session.userId),
          deviceId: session.deviceId,
          code: code,
          label: label,
          colorValue: color,
          countsAs: countsAs.name,
          displayOrder: Value(order),
        ));
    await changes.record(
      table: 'attendance_codes',
      rowId: id,
      operation: 'insert',
      after: {'code': code, 'label': label, 'counts_as': countsAs.name},
    );
  }

  static AttendanceCode _code(AttendanceCodeRow r) => AttendanceCode(
        id: r.id,
        code: r.code,
        label: r.label,
        colorValue: r.colorValue,
        countsAs: CountsAs.values.firstWhere((c) => c.name == r.countsAs, orElse: () => CountsAs.excluded),
        displayOrder: r.displayOrder,
      );

  /// Dates are stored as calendar days at midnight UTC.
  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static String _iso(DateTime d) => _day(d).toIso8601String().substring(0, 10);
}
