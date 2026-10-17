import 'package:drift/drift.dart';

/// Columns every business table carries (blueprint section 4):
/// permanent id, owner institution, timestamps, who changed it,
/// soft delete, a version counter for sync, and the device.
mixin StandardColumns on Table {
  TextColumn get id => text()();
  TextColumn get organizationId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get updatedBy => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
}

@DataClassName('OrganizationRow')
class Organizations extends Table with StandardColumns {
  TextColumn get name => text()();
  TextColumn get shortName => text()();
  TextColumn get institutionType => text()();
  TextColumn get city => text().withDefault(const Constant(''))();
  TextColumn get board => text().nullable()();
  TextColumn get medium => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  IntColumn get brandColor => integer()();
  TextColumn get activeAcademicYear => text()();

  /// Added in schema version 2.
  TextColumn get udiseCode => text().nullable()();

  // Added in schema version 3.
  TextColumn get address => text().nullable()();
  TextColumn get state => text().nullable()();
  TextColumn get website => text().nullable()();
  TextColumn get logoFileName => text().nullable()();

  /// What this institution calls a class and a division, e.g. "Course" / "Batch".
  TextColumn get programLabel => text().nullable()();
  TextColumn get divisionLabel => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ModuleSettingRow')
class ModuleSettings extends Table with StandardColumns {
  TextColumn get moduleId => text()();
  BoolColumn get enabled => boolean()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {organizationId, moduleId},
      ];
}

@DataClassName('AppSettingRow')
class AppSettings extends Table with StandardColumns {
  TextColumn get settingKey => text()();
  TextColumn get settingValue => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {organizationId, settingKey},
      ];
}

/// Academic years such as 2026-27. Status: active, inactive or closed.
/// Only one year is active at a time (checked in AcademicRepository).
@DataClassName('AcademicYearRow')
class AcademicYears extends Table with StandardColumns {
  TextColumn get label => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  TextColumn get status => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A class or course, e.g. "11th Science". Lasts across years.
@DataClassName('ProgramRow')
class Programs extends Table with StandardColumns {
  TextColumn get name => text()();
  TextColumn get stream => text().nullable()();
  IntColumn get levelOrder => integer()();

  /// The class students move to on promotion; empty means they graduate.
  TextColumn get nextProgramId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A division of a class in one academic year, e.g. "A".
@DataClassName('DivisionRow')
class Divisions extends Table with StandardColumns {
  TextColumn get programId => text()();
  TextColumn get academicYearId => text()();
  TextColumn get name => text()();
  IntColumn get capacity => integer().nullable()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// The one permanent record of a student. Placement in a class for a
/// year lives in Enrollments; official numbers in StudentIdentifiers.
@DataClassName('StudentRow')
class Students extends Table with StandardColumns {
  /// e.g. STU-000214. Issued once, never changed or reused.
  TextColumn get displayCode => text()();
  TextColumn get firstName => text()();
  TextColumn get middleName => text().nullable()();
  TextColumn get lastName => text().nullable()();

  /// The name in a second script (Urdu, Marathi...) for certificates.
  TextColumn get altName => text().nullable()();
  TextColumn get gender => text().nullable()();
  DateTimeColumn get dateOfBirth => dateTime().nullable()();
  TextColumn get placeOfBirth => text().nullable()();
  TextColumn get nationality => text().nullable()();
  TextColumn get motherTongue => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get caste => text().nullable()();
  TextColumn get subCaste => text().nullable()();
  TextColumn get bloodGroup => text().nullable()();
  RealColumn get heightCm => real().nullable()();
  RealColumn get weightKg => real().nullable()();
  DateTimeColumn get measuredOn => dateTime().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get photoFileName => text().nullable()();

  /// active, left, alumni, archived
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get admissionDate => dateTime().nullable()();
  TextColumn get previousSchool => text().nullable()();
  DateTimeColumn get leavingDate => dateTime().nullable()();
  TextColumn get leavingReason => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// Values of the institution's own extra fields, as JSON.
  TextColumn get extraJson => text().withDefault(const Constant('{}'))();

  /// Lower-case names, codes, numbers and mobiles used by search.
  TextColumn get searchText => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('GuardianRow')
class Guardians extends Table with StandardColumns {
  TextColumn get name => text()();
  TextColumn get relation => text()();
  TextColumn get mobile => text().nullable()();
  TextColumn get altMobile => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get occupation => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Links students and guardians, so siblings can share a guardian.
@DataClassName('StudentGuardianRow')
class StudentGuardians extends Table with StandardColumns {
  TextColumn get studentId => text()();
  TextColumn get guardianId => text()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// GR number, PEN, APAAR, Saral ID, admission number, Aadhaar.
/// Aadhaar is stored encrypted, with its last four digits and a keyed
/// fingerprint for duplicate checks.
@DataClassName('StudentIdentifierRow')
class StudentIdentifiers extends Table with StandardColumns {
  TextColumn get studentId => text()();
  TextColumn get idType => text()();
  TextColumn get idValue => text()();
  TextColumn get lastFour => text().nullable()();
  TextColumn get fingerprint => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A student's place in one academic year.
@DataClassName('EnrollmentRow')
class Enrollments extends Table with StandardColumns {
  TextColumn get studentId => text()();
  TextColumn get academicYearId => text()();
  TextColumn get divisionId => text()();
  IntColumn get rollNumber => integer().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();

  /// active, left, promoted, detained, graduated, transferred
  TextColumn get status => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Extra student fields an institution defines for itself.
@DataClassName('FieldDefinitionRow')
class FieldDefinitions extends Table with StandardColumns {
  TextColumn get entity => text()();
  TextColumn get fieldKey => text()();
  TextColumn get label => text()();

  /// text, number, date, choice, yesNo
  TextColumn get fieldType => text()();
  TextColumn get optionsJson => text().withDefault(const Constant('[]'))();
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Counters for human-readable numbers such as student codes.
@DataClassName('SequenceRow')
class Sequences extends Table {
  TextColumn get organizationId => text()();
  TextColumn get name => text()();
  IntColumn get nextValue => integer()();

  @override
  Set<Column> get primaryKey => {organizationId, name};
}

/// One Excel or photo import, so it can be reviewed and undone.
@DataClassName('ImportBatchRow')
class ImportBatches extends Table with StandardColumns {
  /// students or photos
  TextColumn get kind => text()();
  TextColumn get sourceName => text()();
  TextColumn get settingsJson => text().withDefault(const Constant('{}'))();
  IntColumn get addedCount => integer().withDefault(const Constant(0))();
  IntColumn get updatedCount => integer().withDefault(const Constant(0))();
  IntColumn get skippedCount => integer().withDefault(const Constant(0))();

  /// done or undone
  TextColumn get status => text().withDefault(const Constant('done'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// What happened to each row of an import. Also remembers each sheet's
/// serial number, so photos named 1.jpg, 2.jpg... can be matched later.
@DataClassName('ImportRowRow')
class ImportRows extends Table {
  TextColumn get id => text()();
  TextColumn get organizationId => text()();
  TextColumn get batchId => text()();
  IntColumn get rowNumber => integer()();
  TextColumn get serialNo => text().nullable()();
  TextColumn get studentId => text().nullable()();

  /// added, updated, skipped, photo
  TextColumn get action => text()();

  /// For photo imports: the photo the student had before, for undo.
  TextColumn get previousValue => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Attendance marks an institution uses (P, A, L, M...).
@DataClassName('AttendanceCodeRow')
class AttendanceCodes extends Table with StandardColumns {
  TextColumn get code => text()();
  TextColumn get label => text()();
  IntColumn get colorValue => integer()();

  /// present, absent, half (half a day present) or excluded (not counted)
  TextColumn get countsAs => text()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One attendance sheet: a division on a date (and, later, a lecture).
@DataClassName('AttendanceSessionRow')
class AttendanceSessions extends Table with StandardColumns {
  TextColumn get academicYearId => text()();
  TextColumn get divisionId => text()();
  DateTimeColumn get date => dateTime()();

  /// Reserved for period-wise attendance; null means the whole day.
  IntColumn get period => integer().nullable()();
  TextColumn get takenBy => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One student's mark in one session.
@DataClassName('AttendanceRecordRow')
class AttendanceRecords extends Table with StandardColumns {
  TextColumn get sessionId => text()();
  TextColumn get enrollmentId => text()();
  TextColumn get studentId => text()();
  TextColumn get code => text()();
  TextColumn get remark => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Holidays and exam days. Weekly offs (Sunday) come from settings.
@DataClassName('CalendarDayRow')
class CalendarDays extends Table with StandardColumns {
  DateTimeColumn get date => dateTime()();

  /// holiday or exam
  TextColumn get dayType => text()();
  TextColumn get note => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Every certificate issued, with the exact details printed on it, so it
/// can be reprinted identically and the serial register is never broken.
@DataClassName('CertificateRow')
class Certificates extends Table with StandardColumns {
  /// bonafide, leaving, noDues, noc, character
  TextColumn get kind => text()();
  IntColumn get serialNo => integer()();

  /// e.g. BON/2026-27/0001
  TextColumn get serialLabel => text()();
  TextColumn get academicYearLabel => text()();
  TextColumn get studentId => text()();
  DateTimeColumn get issuedOn => dateTime()();

  /// The fields as printed (name, class, purpose...), as JSON.
  TextColumn get dataJson => text()();

  /// issued or cancelled
  TextColumn get status => text().withDefault(const Constant('issued'))();
  TextColumn get cancelReason => text().nullable()();
  BoolColumn get isDuplicate => boolean().withDefault(const Constant(false))();
  IntColumn get printCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPrintedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One parent message opened for sending (WhatsApp), kept as a record of
/// who was told what and when. One row per student, so siblings sent in one
/// message share a [batchId]. The daily summary has no student.
@DataClassName('MessageLogRow')
class MessageLogs extends Table with StandardColumns {
  /// absent, streak (absent several days in a row) or summary
  TextColumn get kind => text()();
  TextColumn get batchId => text()();
  TextColumn get studentId => text().nullable()();

  /// Name and class as they were when sent, so history stays readable.
  TextColumn get studentName => text().nullable()();
  TextColumn get classLabel => text().nullable()();

  /// The attendance date the message is about.
  DateTimeColumn get forDate => dateTime()();
  DateTimeColumn get sentAt => dateTime()();
  TextColumn get recipientName => text().nullable()();
  TextColumn get mobile => text().nullable()();
  TextColumn get body => text()();

  /// whatsapp or copy (for now)
  TextColumn get channel => text().withDefault(const Constant('whatsapp'))();

  /// opened: handed to WhatsApp. The app cannot see whether it was delivered.
  TextColumn get status => text().withDefault(const Constant('opened'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A kind of fee: Tuition, Admission, Exam... Amounts are whole rupees.
@DataClassName('FeeHeadRow')
class FeeHeads extends Table with StandardColumns {
  TextColumn get name => text()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// What one class pays in one academic year. [category] null means every
/// student; a structure for a category (OBC, SC...) replaces it for them.
@DataClassName('FeeStructureRow')
class FeeStructures extends Table with StandardColumns {
  TextColumn get academicYearId => text()();
  TextColumn get programId => text()();
  TextColumn get category => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FeeStructureItemRow')
class FeeStructureItems extends Table with StandardColumns {
  TextColumn get structureId => text()();
  TextColumn get headId => text()();
  IntColumn get amount => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Installment due dates of a structure: by [dueDate], [amount] in total
/// should have been paid (cumulative).
@DataClassName('FeeDueDateRow')
class FeeDueDates extends Table with StandardColumns {
  TextColumn get structureId => text()();
  TextColumn get label => text()();
  DateTimeColumn get dueDate => dateTime()();
  IntColumn get amount => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A change to one student's fees for a year: a concession (negative
/// amount) or an extra charge (positive), always with a reason.
@DataClassName('StudentFeeAdjustmentRow')
class StudentFeeAdjustments extends Table with StandardColumns {
  TextColumn get studentId => text()();
  TextColumn get academicYearId => text()();
  TextColumn get headId => text()();
  IntColumn get amount => integer()();
  TextColumn get reason => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A fee receipt. Numbers run per academic year and are never reused;
/// a cancelled receipt stays in the register with its reason.
@DataClassName('FeeReceiptRow')
class FeeReceipts extends Table with StandardColumns {
  IntColumn get serialNo => integer()();

  /// e.g. REC/2026-27/0001
  TextColumn get serialLabel => text()();
  TextColumn get academicYearId => text()();
  TextColumn get academicYearLabel => text()();
  TextColumn get studentId => text()();

  /// As printed on the receipt.
  TextColumn get studentName => text()();
  TextColumn get classLabel => text().withDefault(const Constant(''))();
  TextColumn get grNumber => text().nullable()();
  DateTimeColumn get receivedOn => dateTime()();
  IntColumn get totalAmount => integer()();

  /// Balance for the year left after this payment.
  IntColumn get balanceAfter => integer().nullable()();

  /// cash, upi, cheque, bank
  TextColumn get mode => text()();

  /// UPI transaction id, cheque number, bank reference.
  TextColumn get reference => text().nullable()();
  TextColumn get note => text().nullable()();

  /// issued or cancelled
  TextColumn get status => text().withDefault(const Constant('issued'))();
  TextColumn get cancelReason => text().nullable()();
  IntColumn get printCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FeeReceiptLineRow')
class FeeReceiptLines extends Table with StandardColumns {
  TextColumn get receiptId => text()();
  TextColumn get headId => text()();
  TextColumn get headName => text()();
  IntColumn get amount => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A subject taught in a class (program). Subjects with the same
/// [columnName] are alternatives sharing one result-sheet column (each
/// student takes one, e.g. Urdu / Arabic / Hindi).
@DataClassName('SubjectRow')
class Subjects extends Table with StandardColumns {
  TextColumn get programId => text()();
  TextColumn get name => text()();
  TextColumn get columnName => text()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();

  /// marks or grade (grade subjects are not added to the total)
  TextColumn get kind => text().withDefault(const Constant('marks'))();
  IntColumn get maxMarks => integer().withDefault(const Constant(100))();
  IntColumn get passMarks => integer().withDefault(const Constant(35))();

  @override
  Set<Column> get primaryKey => {id};
}

/// An examination of an academic year (1st Term, 2nd Term...).
@DataClassName('ExamRow')
class Exams extends Table with StandardColumns {
  TextColumn get academicYearId => text()();
  TextColumn get name => text()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();

  /// Counted in the final (yearly) result.
  BoolColumn get countsInFinal => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Which subject of a choice column a student takes in a year.
@DataClassName('SubjectChoiceRow')
class SubjectChoices extends Table with StandardColumns {
  TextColumn get studentId => text()();
  TextColumn get academicYearId => text()();
  TextColumn get columnName => text()();
  TextColumn get subjectId => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A student's marks (or grade) in one subject of one exam.
@DataClassName('MarkRow')
class Marks extends Table with StandardColumns {
  TextColumn get examId => text()();
  TextColumn get studentId => text()();
  TextColumn get subjectId => text()();
  IntColumn get marks => integer().nullable()();
  TextColumn get grade => text().nullable()();
  BoolColumn get absent => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A paper a student submitted (10th marksheet, LC, caste certificate...):
/// whether it was received, its details, and its scanned pages.
@DataClassName('StudentDocumentRow')
class StudentDocuments extends Table with StandardColumns {
  TextColumn get studentId => text()();

  /// Key of the document type (Settings > Student fields > Documents).
  TextColumn get typeKey => text()();

  /// received / pending / notNeeded
  TextColumn get status => text().withDefault(const Constant('received'))();
  TextColumn get number => text().nullable()();
  DateTimeColumn get issuedOn => dateTime().nullable()();
  BoolColumn get isOriginal => boolean().withDefault(const Constant(false))();
  DateTimeColumn get returnedOn => dateTime().nullable()();
  BoolColumn get verified => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();

  /// JSON list of files inside the media folder (pages in order).
  TextColumn get filesJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A staff member who can log in on this device with their own PIN.
/// The administrator (the app PIN) is not stored here.
@DataClassName('StaffMemberRow')
class StaffMembers extends Table with StandardColumns {
  TextColumn get name => text()();
  TextColumn get mobile => text().nullable()();

  /// Key of the role (Settings > Staff > Roles).
  TextColumn get roleKey => text()();

  /// Salted, slow hash of the PIN; never the PIN itself.
  TextColumn get pinHash => text().nullable()();
  IntColumn get pinLength => integer().withDefault(const Constant(4))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  /// JSON list of division ids a teacher works with.
  TextColumn get divisionsJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Append-only history of changes: who, what, when, old and new values.
@DataClassName('AuditEntryRow')
@TableIndex(name: 'audit_by_entity', columns: {#entity, #entityId})
class AuditEntries extends Table {
  TextColumn get id => text()();
  TextColumn get organizationId => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get changes => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get deviceId => text()();
  DateTimeColumn get at => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Changes waiting to be sent to the cloud (Phase 5).
@DataClassName('OutboxEntryRow')
@TableIndex(name: 'outbox_pending', columns: {#syncedAt, #createdAt})
class OutboxEntries extends Table {
  TextColumn get id => text()();
  TextColumn get organizationId => text()();
  TextColumn get targetTable => text()();
  TextColumn get rowId => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per schema upgrade applied on this device.
@DataClassName('MigrationHistoryRow')
class MigrationHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get fromVersion => integer()();
  IntColumn get toVersion => integer()();
  DateTimeColumn get migratedAt => dateTime()();
}
