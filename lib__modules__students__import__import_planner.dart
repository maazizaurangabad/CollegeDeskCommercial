import '../../../core/validation/aadhaar.dart';
import '../../../core/validation/flexible_date.dart';
import '../../../core/validation/mobile.dart';
import '../../../platform/academic/academic_models.dart';
import '../domain/student_models.dart';
import 'import_fields.dart';

enum NameOrder { firstMiddleLast, surnameFirst }

enum ExistingPolicy { skip, fillEmpty }

enum RowSeverity { ok, warning, error }

enum RowIssueCode {
  missingName,
  badDate,
  badNumber,
  badBloodGroup,
  invalidAadhaar,
  invalidMobile,
  duplicateInFile,
  duplicateRoll,
  notPlaced,
  willCreatePlacement,
  alreadyExists,
  possibleDuplicate,
  aadhaarTaken,
  requiredExtraMissing,
  badChoice,
}

class RowIssue {
  const RowIssue(this.code, this.severity, [this.detail]);

  final RowIssueCode code;
  final RowSeverity severity;
  final String? detail;
}

/// Column mapping: one id per column. Ids are ImportField names
/// ("firstName") or "extra:<key>" for the institution's own fields.
typedef ColumnMapping = List<String>;

String fieldId(ImportField f) => f.name;
String extraId(String key) => 'extra:$key';

class ImportOptions {
  ImportOptions({
    this.fixedDivisionId,
    this.createMissingPlacements = true,
    this.existing = ExistingPolicy.skip,
    this.nameOrder = NameOrder.firstMiddleLast,
  });

  /// Put every row in this division (when the sheet has no class column).
  String? fixedDivisionId;
  bool createMissingPlacements;
  ExistingPolicy existing;
  NameOrder nameOrder;
}

/// What the database already holds, used to check rows before saving.
class ExistingData {
  const ExistingData({
    required this.identifierOwners,
    required this.aadhaarOwners,
    required this.nameDob,
    required this.rollsByDivision,
  });

  /// type code -> lower-case value -> student id (Aadhaar excluded).
  final Map<String, Map<String, String>> identifierOwners;

  /// Aadhaar fingerprint -> student id.
  final Map<String, String> aadhaarOwners;

  /// "full name|yyyy-mm-dd" of existing students.
  final Set<String> nameDob;

  /// divisionId -> roll numbers in use (active, not deleted).
  final Map<String, Map<int, String>> rollsByDivision;
}

class PlannedRow {
  PlannedRow({required this.rowNumber, required this.draft, this.serial, this.className, this.divisionName});

  /// Row number as seen in the spreadsheet (1-based).
  final int rowNumber;
  final StudentDraft draft;
  final String? serial;
  final String? className;
  final String? divisionName;
  final List<RowIssue> issues = [];
  String? existingStudentId;

  /// Set when the placement will be created during import.
  (String, String)? pendingPlacement;

  /// Original cells, for the error sheet.
  List<String> source = const [];

  RowSeverity get severity {
    if (issues.any((i) => i.severity == RowSeverity.error)) return RowSeverity.error;
    if (issues.any((i) => i.severity == RowSeverity.warning)) return RowSeverity.warning;
    return RowSeverity.ok;
  }
}

class ImportPlan {
  ImportPlan(this.rows, this.missingPlacements);

  final List<PlannedRow> rows;

  /// (class name, division name) pairs that do not exist yet.
  final Set<(String, String)> missingPlacements;

  int count(RowSeverity s) => rows.where((r) => r.severity == s).length;
  int get existingCount => rows.where((r) => r.existingStudentId != null && r.severity != RowSeverity.error).length;
}

/// Turns spreadsheet rows into checked student drafts. Saves nothing.
class ImportPlanner {
  ImportPlanner({
    required this.academic,
    required this.existing,
    required this.extraFields,
    required this.fingerprint,
  });

  final AcademicSnapshot academic;
  final ExistingData existing;
  final List<ExtraFieldDefinition> extraFields;

  /// Aadhaar fingerprint function (the same keyed hash the database uses).
  final Future<String> Function(String digits) fingerprint;

  Future<ImportPlan> plan(List<List<String>> dataRows, ColumnMapping mapping, ImportOptions options,
      {int firstRowNumber = 2}) async {
    final rows = <PlannedRow>[];
    final missing = <(String, String)>{};
    final seenIds = <String, int>{};
    final seenRolls = <String, int>{};
    final seenAadhaar = <String, int>{};

    for (var i = 0; i < dataRows.length; i++) {
      final cells = dataRows[i];
      if (cells.every((c) => c.trim().isEmpty)) continue;
      String? cell(String id) {
        final index = mapping.indexOf(id);
        if (index < 0 || index >= cells.length) return null;
        final v = cells[index].trim();
        return v.isEmpty ? null : v;
      }

      final row = _buildRow(firstRowNumber + i, cells, cell, options);
      rows.add(row);
      final d = row.draft;

      if (d.firstName.trim().isEmpty) {
        row.issues.add(const RowIssue(RowIssueCode.missingName, RowSeverity.error));
      }

      // Placement.
      if (options.fixedDivisionId != null) {
        d.divisionId = options.fixedDivisionId;
      } else if (row.className != null) {
        final resolved = _resolvePlacement(row.className!, row.divisionName);
        if (resolved != null) {
          d.divisionId = resolved;
        } else if (options.createMissingPlacements) {
          final pair = _placementPair(row.className!, row.divisionName);
          missing.add(pair);
          row.pendingPlacement = pair;
          row.issues.add(RowIssue(RowIssueCode.willCreatePlacement, RowSeverity.warning, '${pair.$1} ${pair.$2}'));
        } else {
          row.issues.add(RowIssue(RowIssueCode.notPlaced, RowSeverity.warning, row.className));
        }
      }

      // Existing student, by any official number.
      for (final entry in d.identifiers.entries) {
        if (entry.key == IdentifierType.aadhaar) continue;
        final owner = existing.identifierOwners[entry.key.code]?[entry.value.toLowerCase()];
        if (owner != null) row.existingStudentId ??= owner;
        final fileKey = '${entry.key.code}:${entry.value.toLowerCase()}';
        if (seenIds.containsKey(fileKey)) {
          row.issues.add(RowIssue(RowIssueCode.duplicateInFile, RowSeverity.error, 'row ${seenIds[fileKey]}'));
        } else {
          seenIds[fileKey] = row.rowNumber;
        }
      }
      final aadhaar = d.identifiers[IdentifierType.aadhaar];
      if (aadhaar != null) {
        final fp = await fingerprint(aadhaar);
        final owner = existing.aadhaarOwners[fp];
        if (seenAadhaar.containsKey(fp)) {
          row.issues.add(RowIssue(RowIssueCode.duplicateInFile, RowSeverity.error, 'row ${seenAadhaar[fp]}'));
        } else {
          seenAadhaar[fp] = row.rowNumber;
        }
        if (owner != null && owner != row.existingStudentId) {
          if (row.existingStudentId == null) {
            row.existingStudentId = owner;
          } else {
            row.issues.add(const RowIssue(RowIssueCode.aadhaarTaken, RowSeverity.error));
          }
        }
      }
      if (row.existingStudentId != null) {
        row.issues.add(RowIssue(
          RowIssueCode.alreadyExists,
          RowSeverity.warning,
          options.existing == ExistingPolicy.skip ? 'skip' : 'fill',
        ));
      } else if (d.dateOfBirth != null &&
          existing.nameDob.contains('${d.fullName.toLowerCase()}|${_iso(d.dateOfBirth!)}')) {
        row.issues.add(const RowIssue(RowIssueCode.possibleDuplicate, RowSeverity.warning));
      }

      // Roll numbers: unique within a division.
      final roll = d.rollNumber;
      final divisionKey = d.divisionId ?? (row.pendingPlacement == null ? null : '${row.pendingPlacement}');
      if (roll != null && divisionKey != null && row.existingStudentId == null) {
        final key = '$divisionKey#$roll';
        final takenBy = d.divisionId == null ? null : existing.rollsByDivision[d.divisionId]?[roll];
        if (seenRolls.containsKey(key)) {
          row.issues.add(RowIssue(RowIssueCode.duplicateRoll, RowSeverity.error, 'row ${seenRolls[key]}'));
        } else if (takenBy != null) {
          row.issues.add(RowIssue(RowIssueCode.duplicateRoll, RowSeverity.error, '$roll'));
        } else {
          seenRolls[key] = row.rowNumber;
        }
      }

      for (final f in extraFields.where((f) => f.isRequired)) {
        if ((d.extra[f.key] ?? '').trim().isEmpty && row.existingStudentId == null) {
          row.issues.add(RowIssue(RowIssueCode.requiredExtraMissing, RowSeverity.error, f.label));
        }
      }
    }
    return ImportPlan(rows, missing);
  }

  PlannedRow _buildRow(int rowNumber, List<String> cells, String? Function(String) cell, ImportOptions options) {
    final d = StudentDraft(nationality: '');
    final issues = <RowIssue>[];

    // Names.
    final full = cell(fieldId(ImportField.fullName));
    if (full != null) {
      final parts = full.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (options.nameOrder == NameOrder.surnameFirst && parts.length >= 2) {
        d.lastName = parts.first;
        d.firstName = parts[1];
        d.middleName = parts.length > 2 ? parts.sublist(2).join(' ') : '';
      } else if (parts.isNotEmpty) {
        d.firstName = parts.first;
        d.lastName = parts.length > 1 ? parts.last : '';
        d.middleName = parts.length > 2 ? parts.sublist(1, parts.length - 1).join(' ') : '';
      }
    }
    d.firstName = cell(fieldId(ImportField.firstName)) ?? d.firstName;
    d.middleName = cell(fieldId(ImportField.middleName)) ?? d.middleName;
    d.lastName = cell(fieldId(ImportField.lastName)) ?? d.lastName;
    d.firstName = _titleCase(d.firstName);
    d.middleName = _titleCase(d.middleName);
    d.lastName = _titleCase(d.lastName);
    d.altName = cell(fieldId(ImportField.altName)) ?? '';

    final gender = cell(fieldId(ImportField.gender));
    if (gender != null) d.gender = _gender(gender);

    DateTime? date(ImportField f) {
      final v = cell(fieldId(f));
      if (v == null) return null;
      final parsed = FlexibleDate.parse(v);
      if (parsed == null) issues.add(RowIssue(RowIssueCode.badDate, RowSeverity.warning, v));
      return parsed;
    }

    d.dateOfBirth = date(ImportField.dateOfBirth);
    d.admissionDate = date(ImportField.admissionDate);
    d.placeOfBirth = cell(fieldId(ImportField.placeOfBirth)) ?? '';
    d.nationality = cell(fieldId(ImportField.nationality)) ?? '';
    d.motherTongue = cell(fieldId(ImportField.motherTongue)) ?? '';
    d.category = cell(fieldId(ImportField.category));
    d.caste = cell(fieldId(ImportField.caste)) ?? '';
    d.subCaste = cell(fieldId(ImportField.subCaste)) ?? '';
    d.address = cell(fieldId(ImportField.address)) ?? '';
    d.previousSchool = cell(fieldId(ImportField.previousSchool)) ?? '';
    d.notes = cell(fieldId(ImportField.notes)) ?? '';

    final blood = cell(fieldId(ImportField.bloodGroup));
    if (blood != null) {
      final normalized = blood
          .toUpperCase()
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll('POSITIVE', '+')
          .replaceAll('POS', '+')
          .replaceAll('VE', '')
          .replaceAll('NEGATIVE', '-')
          .replaceAll('NEG', '-');
      if (StudentChoices.bloodGroups.contains(normalized)) {
        d.bloodGroup = normalized;
      } else {
        issues.add(RowIssue(RowIssueCode.badBloodGroup, RowSeverity.warning, blood));
      }
    }
    double? number(ImportField f) {
      final v = cell(fieldId(f));
      if (v == null) return null;
      final parsed = double.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (parsed == null) issues.add(RowIssue(RowIssueCode.badNumber, RowSeverity.warning, v));
      return parsed;
    }

    d.heightCm = number(ImportField.heightCm);
    d.weightKg = number(ImportField.weightKg);
    if (d.heightCm != null || d.weightKg != null) d.measuredOn = DateTime.now();

    // Official numbers.
    const idFields = {
      ImportField.grNumber: IdentifierType.grNumber,
      ImportField.pen: IdentifierType.pen,
      ImportField.apaar: IdentifierType.apaar,
      ImportField.saralId: IdentifierType.saralId,
      ImportField.admissionNumber: IdentifierType.admissionNumber,
    };
    for (final e in idFields.entries) {
      final v = cell(fieldId(e.key));
      if (v != null) d.identifiers[e.value] = v;
    }
    final aadhaar = cell(fieldId(ImportField.aadhaar));
    if (aadhaar != null) {
      final digits = Aadhaar.normalize(aadhaar);
      if (Aadhaar.isValid(digits)) {
        d.identifiers[IdentifierType.aadhaar] = digits;
      } else {
        issues.add(const RowIssue(RowIssueCode.invalidAadhaar, RowSeverity.warning));
      }
    }

    // Guardians.
    String? phone(ImportField f) {
      final v = cell(fieldId(f));
      if (v == null) return null;
      if (MobileNumber.isValid(v)) return MobileNumber.normalize(v);
      issues.add(RowIssue(RowIssueCode.invalidMobile, RowSeverity.warning, v));
      return null;
    }

    final mobile = phone(ImportField.mobile);
    final altMobile = phone(ImportField.altMobile);
    final father = cell(fieldId(ImportField.fatherName));
    final mother = cell(fieldId(ImportField.motherName));
    final guardian = cell(fieldId(ImportField.guardianName));
    if (father != null) d.guardians.add(GuardianDraft(name: _titleCase(father), relation: 'Father'));
    if (mother != null) d.guardians.add(GuardianDraft(name: _titleCase(mother), relation: 'Mother'));
    if (guardian != null) d.guardians.add(GuardianDraft(name: _titleCase(guardian), relation: 'Guardian'));
    if (d.guardians.isEmpty && (mobile != null || altMobile != null)) {
      // In Maharashtra the middle name is the father's name.
      final fatherGuess = [d.middleName, d.lastName].where((s) => s.isNotEmpty).join(' ');
      d.guardians.add(GuardianDraft(name: fatherGuess, relation: fatherGuess.isEmpty ? 'Guardian' : 'Father'));
    }
    if (d.guardians.isNotEmpty) {
      d.guardians.first
        ..isPrimary = true
        ..mobile = mobile ?? ''
        ..altMobile = altMobile ?? '';
    }

    // Class, division, roll.
    final roll = cell(fieldId(ImportField.rollNumber));
    if (roll != null) {
      d.rollNumber = int.tryParse(roll.replaceAll(RegExp(r'[^0-9]'), ''));
      if (d.rollNumber == null) issues.add(RowIssue(RowIssueCode.badNumber, RowSeverity.warning, roll));
    }

    // The institution's own extra fields.
    for (final f in extraFields) {
      final v = cell(extraId(f.key));
      if (v == null) continue;
      switch (f.type) {
        case 'date':
          final parsed = FlexibleDate.parse(v);
          if (parsed == null) {
            issues.add(RowIssue(RowIssueCode.badDate, RowSeverity.warning, v));
          } else {
            d.extra[f.key] = _iso(parsed);
          }
        case 'yesNo':
          final yes = ['yes', 'y', 'true', '1', 'हो', 'होय'].contains(v.toLowerCase());
          d.extra[f.key] = '$yes';
        case 'number':
          if (double.tryParse(v) == null) {
            issues.add(RowIssue(RowIssueCode.badNumber, RowSeverity.warning, v));
          } else {
            d.extra[f.key] = v;
          }
        case 'choice':
          final match = f.options.where((o) => o.toLowerCase() == v.toLowerCase()).firstOrNull;
          if (match == null) {
            issues.add(RowIssue(RowIssueCode.badChoice, RowSeverity.warning, v));
          } else {
            d.extra[f.key] = match;
          }
        default:
          d.extra[f.key] = v;
      }
    }

    final row = PlannedRow(
      rowNumber: rowNumber,
      draft: d,
      serial: cell(fieldId(ImportField.serialNo)),
      className: cell(fieldId(ImportField.className)),
      divisionName: cell(fieldId(ImportField.divisionName)),
    )..source = cells;
    row.issues.addAll(issues);
    return row;
  }

  /// Finds the division for "11th Science" + "A", or "11th Science A" alone.
  String? _resolvePlacement(String className, String? divisionName) {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0900-\u097F]'), '');
    var program = academic.programs.where((p) => norm(p.name) == norm(className)).firstOrNull;
    var division = divisionName;
    if (program == null && divisionName == null) {
      final parts = className.trim().split(RegExp(r'\s+'));
      if (parts.length > 1) {
        final head = parts.sublist(0, parts.length - 1).join(' ');
        program = academic.programs.where((p) => norm(p.name) == norm(head)).firstOrNull;
        if (program != null) division = parts.last;
      }
    }
    if (program == null) return null;
    final divisions = academic.divisionsOf(program.id);
    if (division == null) return divisions.length == 1 ? divisions.single.id : null;
    return divisions.where((d) => norm(d.name) == norm(division!)).firstOrNull?.id;
  }

  (String, String) _placementPair(String className, String? divisionName) =>
      (className.trim(), (divisionName ?? 'A').trim());

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    final isAllCaps = s == s.toUpperCase() && RegExp(r'[A-Z]').hasMatch(s);
    if (!isAllCaps) return s.trim();
    return s
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  static String? _gender(String v) {
    final g = v.trim().toLowerCase();
    if (['m', 'male', 'boy', 'b', 'पुरुष', 'मुलगा'].contains(g)) return 'Male';
    if (['f', 'female', 'girl', 'g', 'स्त्री', 'मुलगी'].contains(g)) return 'Female';
    return g.isEmpty ? null : 'Other';
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
