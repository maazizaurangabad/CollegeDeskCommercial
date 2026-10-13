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
