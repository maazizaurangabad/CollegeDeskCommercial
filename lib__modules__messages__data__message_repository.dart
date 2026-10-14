import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/org_scoped_repository.dart';
import '../../../core/ids/uuid7.dart';
import '../../../core/validation/mobile.dart';
import '../../../platform/data/app_settings_repository.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/attendance_models.dart';
import '../../students/data/student_repository.dart';
import '../domain/message_models.dart';

/// One class on the day summary.
class DivisionDaySummary {
  const DivisionDaySummary({
    required this.label,
    required this.marked,
    required this.present,
    required this.absentees,
  });

  final String label;

  /// False when attendance was not saved for this class.
  final bool marked;
  final int present;

  /// (roll number, name, mark), in roll order.
  final List<(int?, String, String)> absentees;

  int get absent => absentees.length;
}

class DaySummary {
  const DaySummary({required this.date, required this.divisions});

  final DateTime date;
  final List<DivisionDaySummary> divisions;

  int get present => divisions.fold(0, (sum, d) => sum + d.present);
  int get absent => divisions.fold(0, (sum, d) => sum + d.absent);
  bool get anyMarked => divisions.any((d) => d.marked);
}

/// Messages to parents: who to tell, what to say, and the record of what
/// was sent. Sending itself is done by WhatsApp; this keeps the rules.
class MessageRepository extends OrgScopedRepository {
  MessageRepository(super.db, super.session, this.settings, this.attendance, this.students);

  final AppSettingsRepository settings;
  final AttendanceRepository attendance;
  final StudentRepository students;

  static const _table = 'message_logs';
  static const absentTemplateKey = 'messages.template.absent';
  static const streakTemplateKey = 'messages.template.streak';
  static const streakDaysKey = 'messages.streak_days';
  static const codesKey = 'messages.codes';

  static final _dateWords = DateFormat('d MMM y');

  // ================================================================ settings

  Future<MessageSettings> loadSettings() async {
    final absent = await settings.getValue(absentTemplateKey);
    final streak = await settings.getValue(streakTemplateKey);
    final days = int.tryParse(await settings.getValue(streakDaysKey) ?? '');
    final rawCodes = await settings.getValue(codesKey);
    final Set<String> codes;
    if (rawCodes == null) {
      // Absent marks only; leave (L) is not messaged unless switched on.
      codes = {
        for (final c in await attendance.codes())
          if (c.countsAs == CountsAs.absent && c.code != 'L') c.code,
      };
    } else {
      codes = (jsonDecode(rawCodes) as List<dynamic>).map((e) => '$e').toSet();
    }
    return MessageSettings(
      absentTemplate: (absent == null || absent.trim().isEmpty) ? MessageSettings.defaultAbsentTemplate : absent,
      streakTemplate: (streak == null || streak.trim().isEmpty) ? MessageSettings.defaultStreakTemplate : streak,
      streakDays: (days == null || days < 2) ? MessageSettings.defaultStreakDays : days,
      codes: codes,
    );
  }

  Future<void> saveSettings(MessageSettings value) async {
    await settings.setValue(absentTemplateKey, value.absentTemplate.trim());
    await settings.setValue(streakTemplateKey, value.streakTemplate.trim());
    await settings.setValue(streakDaysKey, '${value.streakDays < 2 ? 2 : value.streakDays}');
    await settings.setValue(codesKey, jsonEncode(value.codes.toList()..sort()));
  }

  /// Puts the standard texts back (the mark choice is kept).
  Future<void> resetTemplates() async {
    await settings.setValue(absentTemplateKey, MessageSettings.defaultAbsentTemplate);
    await settings.setValue(streakTemplateKey, MessageSettings.defaultStreakTemplate);
    await settings.setValue(streakDaysKey, '${MessageSettings.defaultStreakDays}');
  }

  // ================================================================ families

  /// Everyone to message for [date]: absent students grouped by their
  /// parent's mobile (siblings get one message), each with the text ready.
  Future<List<AbsentFamily>> absentFamilies(
    DateTime date, {
    required String institution,
    required Map<String, String> divisionLabels,
  }) async {
    final setup = await loadSettings();
    final marks = (await attendance.absentOn(date)).where((a) => setup.codes.contains(a.code)).toList();
    if (marks.isEmpty) return [];
    final ids = marks.map((m) => m.studentId).toSet();
    final names = await students.namesFor(ids);
    final rolls = await _rolls(ids);
    final streaks = await attendance.absentStreaks(ids, date);
    final contacts = await _contacts(ids);
    final sent = await _sentOn(date);

    final byKey = <String, List<AbsentStudent>>{};
    final recipient = <String, String?>{};
    final mobileOf = <String, String?>{};
    for (final m in marks) {
      final s = names[m.studentId];
      if (s == null) continue;
      final student = AbsentStudent(
        studentId: m.studentId,
        fullName: s.fullName,
        className: divisionLabels[m.divisionId] ?? '',
        divisionId: m.divisionId,
        code: m.code,
        streak: streaks[m.studentId] ?? 1,
        rollNumber: rolls[(m.studentId, m.divisionId)],
      );
      final contact = contacts[m.studentId];
      final key = contact?.$2 ?? 'none:${m.studentId}';
      (byKey[key] ??= []).add(student);
      recipient[key] ??= contact?.$1;
      mobileOf[key] = contact?.$2;
    }

    final out = <AbsentFamily>[];
    for (final e in byKey.entries) {
      final kids = e.value..sort(_byClassRollName);
      final streak = kids.map((k) => k.streak).reduce((a, b) => a < b ? a : b);
      final kind = streak >= setup.streakDays ? MessageKind.streak : MessageKind.absent;
      final times = kids.map((k) => sent[k.studentId]).toList();
      out.add(AbsentFamily(
        students: kids,
        recipientName: recipient[e.key],
        mobile: mobileOf[e.key],
        kind: kind,
        body: fillBody(
          kind == MessageKind.streak ? setup.streakTemplate : setup.absentTemplate,
          kids,
          date: date,
          days: streak,
          institution: institution,
        ),
        sentAt: times.contains(null) ? null : times.whereType<DateTime>().reduce((a, b) => a.isAfter(b) ? a : b),
      ));
    }
    out.sort((a, b) => _byClassRollName(a.students.first, b.students.first));
    return out;
  }

  /// The message for one family, from a template.
  static String fillBody(
    String template,
    List<AbsentStudent> kids, {
    required DateTime date,
    required int days,
    required String institution,
  }) {
    final classes = <String>[];
    for (final k in kids) {
      if (k.className.isNotEmpty && !classes.contains(k.className)) classes.add(k.className);
    }
    final marks = <String>{for (final k in kids) k.code};
    return MessagePlaceholders.fill(template, {
      MessagePlaceholders.student: _joinNames(kids.map((k) => k.fullName).toList()),
      MessagePlaceholders.className: classes.join(' / '),
      MessagePlaceholders.roll: kids.map((k) => k.rollNumber?.toString() ?? '-').join(', '),
      MessagePlaceholders.date: _dateWords.format(date),
      MessagePlaceholders.days: '$days',
      MessagePlaceholders.institution: institution,
      MessagePlaceholders.mark: marks.join(', '),
    });
  }

  static String _joinNames(List<String> names) {
    if (names.length <= 1) return names.join();
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  static int _byClassRollName(AbsentStudent a, AbsentStudent b) {
    final c = a.className.compareTo(b.className);
    if (c != 0) return c;
    final r = (a.rollNumber ?? 9999).compareTo(b.rollNumber ?? 9999);
    return r != 0 ? r : a.fullName.compareTo(b.fullName);
  }

  /// studentId -> (parent's name, ten-digit mobile). The primary guardian's
  /// number first, then any other guardian's; invalid numbers are skipped.
  Future<Map<String, (String, String)>> _contacts(Set<String> ids) async {
    final links = await (db.select(db.studentGuardians)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.studentId.isIn(ids)))
        .get();
    if (links.isEmpty) return {};
    final guardians = {
      for (final g in await (db.select(db.guardians)
            ..where((t) =>
                t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.id.isIn(links.map((l) => l.guardianId))))
          .get())
        g.id: g,
    };
    final out = <String, (String, String)>{};
    for (final id in ids) {
      final mine = links.where((l) => l.studentId == id).toList()
        ..sort((a, b) => (b.isPrimary ? 1 : 0).compareTo(a.isPrimary ? 1 : 0));
      (String, String)? pick;
      for (final pass in [true, false]) {
        for (final link in mine) {
          final g = guardians[link.guardianId];
          if (g == null) continue;
          final number = pass ? g.mobile : g.altMobile;
          if (number != null && MobileNumber.isValid(number)) {
            pick = (g.name, MobileNumber.normalize(number));
            break;
          }
        }
        if (pick != null) break;
      }
      if (pick != null) out[id] = pick;
    }
    return out;
  }

  Future<Map<(String, String), int?>> _rolls(Set<String> ids) async {
    final rows = await (db.select(db.enrollments)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull() & t.studentId.isIn(ids)))
        .get();
    return {for (final r in rows) (r.studentId, r.divisionId): r.rollNumber};
  }

  /// studentId -> when a parent message about [date] was last opened.
  Future<Map<String, DateTime>> _sentOn(DateTime date) async {
    final rows = await (db.select(db.messageLogs)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.deletedAt.isNull() &
              t.forDate.equals(_day(date)) &
              t.kind.isIn([MessageKind.absent.name, MessageKind.streak.name])))
        .get();
    final out = <String, DateTime>{};
    for (final r in rows) {
      final id = r.studentId;
      if (id == null) continue;
      final previous = out[id];
      if (previous == null || r.sentAt.isAfter(previous)) out[id] = r.sentAt;
    }
    return out;
  }

  // ================================================================= record

  /// Records that a family's message was handed to WhatsApp (or copied).
  /// [body] is the text actually sent, when the user changed it.
  Future<void> recordSent(AbsentFamily family, DateTime date, {String channel = 'whatsapp', String? body}) {
    return db.transaction(() async {
      final ts = now();
      final batch = Uuid7.generate(ts);
      for (final s in family.students) {
        await _insert(
          batch: batch,
          ts: ts,
          kind: family.kind,
          date: date,
          studentId: s.studentId,
          studentName: s.fullName,
          classLabel: s.className,
          recipient: family.recipientName,
          mobile: family.mobile,
          body: body ?? family.body,
          channel: channel,
        );
      }
    });
  }

  /// Records that the day summary was shared or copied.
  Future<void> recordSummary(DateTime date, String body, {String channel = 'whatsapp'}) {
    return db.transaction(() async {
      final ts = now();
      await _insert(
        batch: Uuid7.generate(ts),
        ts: ts,
        kind: MessageKind.summary,
        date: date,
        body: body,
        channel: channel,
      );
    });
  }

  Future<void> _insert({
    required String batch,
    required DateTime ts,
    required MessageKind kind,
    required DateTime date,
    required String body,
    required String channel,
    String? studentId,
    String? studentName,
    String? classLabel,
    String? recipient,
    String? mobile,
  }) async {
    final id = Uuid7.generate(ts);
    await db.into(db.messageLogs).insert(MessageLogsCompanion.insert(
          id: id,
          organizationId: orgId,
          createdAt: ts,
          updatedAt: ts,
          createdBy: Value(session.userId),
          updatedBy: Value(session.userId),
          deviceId: session.deviceId,
          kind: kind.name,
          batchId: batch,
          studentId: Value(studentId),
          studentName: Value(studentName),
          classLabel: Value(classLabel),
          forDate: _day(date),
          sentAt: ts,
          recipientName: Value(recipient),
          mobile: Value(mobile),
          body: body,
          channel: Value(channel),
        ));
    await changes.record(table: _table, rowId: id, operation: 'insert', after: {
      'kind': kind.name,
      'batch_id': batch,
      'student_id': studentId,
      'for_date': _iso(date),
      'mobile': mobile,
      'channel': channel,
    });
  }

  // ================================================================ history

  /// Messages sent, newest first. Siblings sent together come back as one record.
  Future<List<MessageRecord>> history({DateTime? from, DateTime? to, String query = '', int limit = 5000}) async {
    final q = query.trim().toLowerCase();
    final select = db.select(db.messageLogs)
      ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.sentAt)]);
    if (from != null) select.where((t) => t.forDate.isBiggerOrEqualValue(_day(from)));
    if (to != null) select.where((t) => t.forDate.isSmallerOrEqualValue(_day(to)));
    final rows = await select.get();

    final order = <String>[];
    final groups = <String, List<MessageLogRow>>{};
    for (final r in rows) {
      if (!groups.containsKey(r.batchId)) order.add(r.batchId);
      (groups[r.batchId] ??= []).add(r);
    }
    final out = <MessageRecord>[];
    for (final id in order) {
      final g = groups[id]!;
      final first = g.first;
      final record = MessageRecord(
        batchId: id,
        kind: MessageKind.byName(first.kind),
        forDate: first.forDate,
        sentAt: first.sentAt,
        studentNames: [for (final r in g) if ((r.studentName ?? '').isNotEmpty) r.studentName!],
        classNames: {for (final r in g) if ((r.classLabel ?? '').isNotEmpty) r.classLabel!}.toList(),
        body: first.body,
        channel: first.channel,
        status: first.status,
        recipientName: first.recipientName,
        mobile: first.mobile,
      );
      if (q.isNotEmpty) {
        final text = '${record.studentNames.join(' ')} ${record.classNames.join(' ')} ${record.mobile ?? ''} '
                '${record.recipientName ?? ''}'
            .toLowerCase();
        if (!text.contains(q)) continue;
      }
      out.add(record);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// How many parent messages (not summaries) were opened about [date].
  Future<int> countForDate(DateTime date) async {
    final rows = await (db.select(db.messageLogs)
          ..where((t) =>
              t.organizationId.equals(orgId) &
              t.deletedAt.isNull() &
              t.forDate.equals(_day(date)) &
              t.kind.equals(MessageKind.summary.name).not()))
        .get();
    return rows.map((r) => r.batchId).toSet().length;
  }

  // ================================================================ summary

  /// Class-wise counts and absent names for [date], in the order given.
  /// Classes with no students that day are left out.
  Future<DaySummary> daySummary(DateTime date, {required List<(String, String)> divisions}) async {
    final d = _day(date);
    final codes = {for (final c in await attendance.codes()) c.code: c};
    final sessions = await (db.select(db.attendanceSessions)
          ..where((t) => t.organizationId.equals(orgId) & t.date.equals(d) & t.deletedAt.isNull()))
        .get();
    final sessionOf = {for (final s in sessions) s.divisionId: s.id};
    final records = sessions.isEmpty
        ? <AttendanceRecordRow>[]
        : await (db.select(db.attendanceRecords)
              ..where((t) => t.deletedAt.isNull() & t.sessionId.isIn(sessions.map((s) => s.id))))
            .get();
    final absentRecords =
        records.where((r) => codes[r.code]?.countsAs == CountsAs.absent).toList();
    final names = await students.namesFor(absentRecords.map((r) => r.studentId));
    final enrollmentIds = absentRecords.map((r) => r.enrollmentId).toSet();
    final rolls = enrollmentIds.isEmpty
        ? <String, int?>{}
        : {
            for (final e in await (db.select(db.enrollments)..where((t) => t.id.isIn(enrollmentIds))).get())
              e.id: e.rollNumber,
          };
    final unmarked =
        (await attendance.unmarkedDivisions(d, divisions.map((x) => x.$1).where((id) => !sessionOf.containsKey(id))))
            .toSet();

    final out = <DivisionDaySummary>[];
    for (final (id, label) in divisions) {
      final sessionId = sessionOf[id];
      if (sessionId == null) {
        if (unmarked.contains(id)) {
          out.add(DivisionDaySummary(label: label, marked: false, present: 0, absentees: const []));
        }
        continue;
      }
      var present = 0;
      final absentees = <(int?, String, String)>[];
      for (final r in records.where((r) => r.sessionId == sessionId)) {
        switch (codes[r.code]?.countsAs) {
          case CountsAs.present:
          case CountsAs.half:
            present++;
          case CountsAs.absent:
            absentees.add((rolls[r.enrollmentId], names[r.studentId]?.fullName ?? '', r.code));
          default:
            break;
        }
      }
      absentees.sort((a, b) {
        final c = (a.$1 ?? 9999).compareTo(b.$1 ?? 9999);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
      out.add(DivisionDaySummary(label: label, marked: true, present: present, absentees: absentees));
    }
    return DaySummary(date: d, divisions: out);
  }

  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static String _iso(DateTime d) => _day(d).toIso8601String().substring(0, 10);
}
