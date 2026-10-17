import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/org_scoped_repository.dart';
import '../../../core/ids/uuid7.dart';
import '../../../core/validation/date_words.dart';
import '../../students/data/student_repository.dart';
import '../../students/domain/student_models.dart';
import '../domain/certificate_models.dart';

/// Issuing certificates: filling them from the student record, numbering
/// them per type and academic year, the issue register, reprints and
/// cancellations. A leaving certificate can also mark the student as left.
class CertificateRepository extends OrgScopedRepository {
  CertificateRepository(super.db, super.session, this.students, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final StudentRepository students;
  final DateTime Function() _clock;

  static final _dates = DateFormat('dd/MM/yyyy');

  /// Everything the certificate can show, taken from the student's record.
  /// The clerk can change or complete any value before issuing.
  Future<Map<String, String>> prefill(String studentId, {required Map<String, String> divisionLabels}) async {
    final detail = await students.load(studentId);
    if (detail == null) throw const CertificateException(CertificateIssue.notFound);
    final d = detail.draft;
    final active = detail.activeEnrollment;
    final latest = active ?? (detail.enrollments.isEmpty ? null : detail.enrollments.first);
    final first = detail.enrollments.isEmpty ? null : detail.enrollments.last;
    final mother = detail.guardians.where((g) => g.relation == 'Mother').firstOrNull?.name ?? '';
    final fatherGuardian = detail.guardians.where((g) => g.relation == 'Father').firstOrNull;
    final father = fatherGuardian?.name ?? [d.middleName, d.lastName].where((s) => s.isNotEmpty).join(' ');
    final year = await _yearLabel(latest?.academicYearId);
    String date(DateTime? x) => x == null ? '' : _dates.format(x);
    final className = divisionLabels[latest?.divisionId] ?? '';
    return {
      CertField.name: d.fullName,
      CertField.fatherName: d.middleName,
      CertField.surname: d.lastName,
      CertField.motherName: mother,
      CertField.gender: d.gender ?? '',
      CertField.grNumber: detail.identifier(IdentifierType.grNumber) ?? '',
      CertField.studentCode: detail.displayCode,
      CertField.pen: detail.identifier(IdentifierType.pen) ?? '',
      CertField.apaar: detail.identifier(IdentifierType.apaar) ?? '',
      CertField.saralId: detail.identifier(IdentifierType.saralId) ?? '',
      CertField.className: className,
      CertField.rollNumber: latest?.rollNumber?.toString() ?? '',
      CertField.academicYear: year,
      CertField.dateOfBirth: date(d.dateOfBirth),
      CertField.dateOfBirthWords: d.dateOfBirth == null ? '' : DateWords.date(d.dateOfBirth!),
      CertField.placeOfBirth: d.placeOfBirth,
      CertField.nationality: d.nationality.isEmpty ? 'Indian' : d.nationality,
      CertField.motherTongue: d.motherTongue,
      CertField.religion: '',
      CertField.casteSubcaste: [d.caste, d.subCaste].where((s) => s.isNotEmpty).join(' - '),
      CertField.category: d.category ?? '',
      CertField.previousSchool: d.previousSchool,
      CertField.admissionDateClass: [
        date(d.admissionDate ?? first?.startDate),
        if (first != null) divisionLabels[first.divisionId] ?? '',
      ].where((s) => s.isNotEmpty).join(', '),
      CertField.progress: 'Good',
      CertField.conduct: 'Good',
      CertField.leavingDate: date(detail.leavingDate ?? _clock()),
      CertField.studyingSince: [
        className,
        if (latest != null) 'since ${date(latest.startDate)}',
      ].where((s) => s.isNotEmpty).join(' '),
      CertField.leavingReason: detail.leavingReason ?? '',
      CertField.remarks: '',
      CertField.purpose: '',
      CertField.examResult: '',
      CertField.examDetails: '',
      CertField.promotion: '',
      // Nirgam Utara rows.
      CertField.parents: [
        if (father.isNotEmpty) 'Father: $father',
        if (mother.isNotEmpty) 'Mother: $mother',
      ].join('; '),
      CertField.caste: [d.caste, d.subCaste].where((s) => s.isNotEmpty).join(' - '),
      CertField.occupation: fatherGuardian?.occupation ?? '',
      CertField.admissionDate: date(d.admissionDate ?? first?.startDate),
      CertField.classAtAdmission: first == null ? '' : divisionLabels[first.divisionId] ?? '',
      CertField.classAtLeaving: className,
      CertField.identificationMarks: '',
      CertField.signatory: 'Principal',
      // Form-15A: "11th Science A" -> standard "11th", faculty "Science".
      CertField.standard: _standardOf(className),
      CertField.faculty: _facultyOf(className),
    };
  }

  /// Issues a certificate with the next serial number for its type and year.
  /// A second leaving certificate for the same student is a duplicate: it
  /// keeps the original number and is printed "DUPLICATE".
  Future<CertificateRecord> issue({
    required CertificateKind kind,
    required String studentId,
    required Map<String, String> fields,
    required String academicYearLabel,
    bool markLeft = false,
  }) {
    return db.transaction(() async {
      final ts = now();
      final today = DateTime.utc(_clock().year, _clock().month, _clock().day);
      CertificateRow? original;
      if (kind == CertificateKind.leaving || kind == CertificateKind.nirgam) {
        original = await (db.select(db.certificates)
              ..where((t) =>
                  t.organizationId.equals(orgId) &
                  t.studentId.equals(studentId) &
                  t.kind.equals(kind.name) &
                  t.status.equals(CertificateStatus.issued.name) &
                  t.isDuplicate.equals(false) &
                  t.deletedAt.isNull()))
            .getSingleOrNull();
      }
      final int serial;
      final String label;
      if (original != null) {
        serial = original.serialNo;
        label = original.serialLabel;
      } else {
        serial = await _nextSerial(kind, academicYearLabel);
        label = '${kind.prefix}/$academicYearLabel/${serial.toString().padLeft(4, '0')}';
      }
      final id = Uuid7.generate(ts);
      await db.into(db.certificates).insert(CertificatesCompanion.insert(
            id: id,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            kind: kind.name,
            serialNo: serial,
            serialLabel: label,
            academicYearLabel: academicYearLabel,
            studentId: studentId,
            issuedOn: today,
            dataJson: jsonEncode(fields),
            isDuplicate: Value(original != null),
          ));
      await changes.record(
        table: 'certificates',
        rowId: id,
        operation: 'insert',
        after: {'kind': kind.name, 'serial': label, 'student_id': studentId, 'duplicate': original != null},
      );
      if (markLeft && (kind == CertificateKind.leaving || kind == CertificateKind.nirgam) && original == null) {
        final detail = await students.load(studentId);
        if (detail != null && detail.status == StudentStatus.active) {
          final leaving = _parse(fields[CertField.leavingDate]) ?? today;
          await students.markLeft(studentId, date: leaving, reason: fields[CertField.leavingReason] ?? '');
        }
      }
      return (await get(id))!;
    });
  }

  Future<CertificateRecord?> get(String id) async {
    final row = await (db.select(db.certificates)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
        .getSingleOrNull();
    return row == null ? null : _record(row);
  }

  /// The register, newest first; optionally one type or one student.
  Future<List<CertificateRecord>> list({CertificateKind? kind, String? studentId, int limit = 500}) async {
    final rows = await (db.select(db.certificates)
          ..where((t) {
            var c = t.organizationId.equals(orgId) & t.deletedAt.isNull();
            if (kind != null) c = c & t.kind.equals(kind.name);
            if (studentId != null) c = c & t.studentId.equals(studentId);
            return c;
          })
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
    return rows.map(_record).toList();
  }

  /// Counts each printing, so reprints are visible in the register.
  Future<void> recordPrint(String id) {
    return db.transaction(() async {
      final row = await (db.select(db.certificates)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
          .getSingle();
      await (db.update(db.certificates)..where((t) => t.id.equals(id))).write(CertificatesCompanion(
        printCount: Value(row.printCount + 1),
        lastPrintedAt: Value(now()),
        updatedAt: Value(now()),
        rowVersion: Value(row.rowVersion + 1),
      ));
      await changes.record(
        table: 'certificates',
        rowId: id,
        operation: row.printCount == 0 ? 'print' : 'reprint',
        after: {'serial': row.serialLabel, 'print_count': row.printCount + 1},
      );
    });
  }

  /// A cancelled certificate stays in the register with its reason;
  /// its number is never given to another certificate.
  Future<void> cancel(String id, String reason) {
    return db.transaction(() async {
      final row = await (db.select(db.certificates)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
          .getSingleOrNull();
      if (row == null) throw const CertificateException(CertificateIssue.notFound);
      if (row.status == CertificateStatus.cancelled.name) {
        throw const CertificateException(CertificateIssue.alreadyCancelled);
      }
      await (db.update(db.certificates)..where((t) => t.id.equals(id))).write(CertificatesCompanion(
        status: Value(CertificateStatus.cancelled.name),
        cancelReason: Value(reason.trim()),
        updatedAt: Value(now()),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(row.rowVersion + 1),
      ));
      await changes.record(
        table: 'certificates',
        rowId: id,
        operation: 'cancel',
        before: {'status': row.status},
        after: {'status': 'cancelled', 'reason': reason.trim()},
      );
    });
  }

  Future<int> _nextSerial(CertificateKind kind, String yearLabel) async {
    final name = 'cert.${kind.name}.$yearLabel';
    final seq = await (db.select(db.sequences)
          ..where((t) => t.organizationId.equals(orgId) & t.name.equals(name)))
        .getSingleOrNull();
    if (seq == null) {
      await db.into(db.sequences).insert(SequencesCompanion.insert(organizationId: orgId, name: name, nextValue: 2));
      return 1;
    }
    await (db.update(db.sequences)..where((t) => t.organizationId.equals(orgId) & t.name.equals(name)))
        .write(SequencesCompanion(nextValue: Value(seq.nextValue + 1)));
    return seq.nextValue;
  }

  Future<String> _yearLabel(String? academicYearId) async {
    if (academicYearId == null) return '';
    final row = await (db.select(db.academicYears)..where((t) => t.id.equals(academicYearId))).getSingleOrNull();
    return row?.label ?? '';
  }

  static String _standardOf(String className) {
    final words = className.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return words.isEmpty ? '' : words.first;
  }

  static String _facultyOf(String className) {
    final words = className.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= 1) return '';
    // The last word is the division (A, B...) when it is short.
    final end = words.length > 2 && words.last.length <= 2 ? words.length - 1 : words.length;
    return words.sublist(1, end).join(' ');
  }

  static DateTime? _parse(String? ddmmyyyy) {
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(ddmmyyyy?.trim() ?? '');
    if (m == null) return null;
    return DateTime.utc(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }

  static CertificateRecord _record(CertificateRow r) => CertificateRecord(
        id: r.id,
        kind: CertificateKind.byName(r.kind) ?? CertificateKind.bonafide,
        serialLabel: r.serialLabel,
        studentId: r.studentId,
        issuedOn: r.issuedOn,
        fields: CertificateRecord.decode(r.dataJson),
        status: r.status == 'cancelled' ? CertificateStatus.cancelled : CertificateStatus.issued,
        isDuplicate: r.isDuplicate,
        printCount: r.printCount,
        cancelReason: r.cancelReason,
        lastPrintedAt: r.lastPrintedAt,
        createdBy: r.createdBy,
      );
}
