import 'package:flutter/foundation.dart';

import '../../../core/validation/aadhaar.dart';
import 'import_fields.dart';
import 'import_planner.dart';
import 'import_repository.dart';

/// What happened to one spreadsheet row, from the actual save.
enum ImportRowKind {
  /// Not saved: the row has an error (missing name, impossible date...).
  skipped,

  /// Not saved: the student is already in the app (and nothing was filled).
  alreadySaved,

  /// Saved, but the same name and date of birth already existed: check.
  possibleDuplicate,

  /// Saved, with something to check (e.g. an invalid mobile left out).
  savedWithWarnings,

  /// Saved with nothing to check.
  saved,
}

/// Issues that only describe what the import did, not a problem.
const _informational = {RowIssueCode.alreadyExists, RowIssueCode.willCreatePlacement};

@immutable
class ImportReportEntry {
  const ImportReportEntry({required this.row, required this.kind, this.studentId});

  final PlannedRow row;
  final ImportRowKind kind;

  /// The saved (or already existing) student, when there is one.
  final String? studentId;

  int get rowNumber => row.rowNumber;

  /// The problems worth showing for this row (most serious first).
  List<RowIssue> get problems => [
        ...row.issues.where((i) => i.severity == RowSeverity.error),
        ...row.issues.where((i) => i.severity == RowSeverity.warning && !_informational.contains(i.code)),
        if (kind == ImportRowKind.alreadySaved) ...row.issues.where((i) => i.code == RowIssueCode.alreadyExists),
      ];
}

/// The result of one import, kept until the user closes it or starts
/// another import. Built from the plan and the real save results, so the
/// counts are never worked out separately.
@immutable
class ImportReport {
  const ImportReport({
    required this.batchId,
    required this.sourceName,
    required this.headers,
    required this.mapping,
    required this.entries,
    this.added = 0,
    this.updated = 0,
    this.resolved = const {},
  });

  factory ImportReport.from({
    required ImportPlan plan,
    required ImportResult result,
    required String sourceName,
    required List<String> headers,
    required ColumnMapping mapping,
  }) {
    final outcome = {for (final o in result.outcomes) o.rowNumber: o};
    return ImportReport(
      batchId: result.batchId,
      added: result.added,
      updated: result.updated,
      sourceName: sourceName,
      headers: headers,
      mapping: mapping,
      entries: [
        for (final row in plan.rows)
          () {
            final o = outcome[row.rowNumber];
            final action = o?.action ?? (row.severity == RowSeverity.error ? 'skipped' : 'added');
            final ImportRowKind kind;
            if (action == 'skipped') {
              kind = row.severity == RowSeverity.error ? ImportRowKind.skipped : ImportRowKind.alreadySaved;
            } else if (row.issues.any((i) => i.code == RowIssueCode.possibleDuplicate)) {
              kind = ImportRowKind.possibleDuplicate;
            } else if (row.issues.any((i) => i.severity != RowSeverity.error && !_informational.contains(i.code))) {
              kind = ImportRowKind.savedWithWarnings;
            } else {
              kind = ImportRowKind.saved;
            }
            return ImportReportEntry(row: row, kind: kind, studentId: o?.studentId ?? row.existingStudentId);
          }(),
      ],
    );
  }

  final String batchId;
  final String sourceName;

  /// From the save itself.
  final int added;
  final int updated;

  /// The sheet's column headings and what each column was matched to.
  final List<String> headers;
  final ColumnMapping mapping;
  final List<ImportReportEntry> entries;

  /// Rows the user has since added by hand (from this report).
  final Set<int> resolved;

  int get total => entries.length;
  int count(ImportRowKind kind) => entries.where((e) => e.kind == kind).length;
  List<ImportReportEntry> of(ImportRowKind kind) => entries.where((e) => e.kind == kind).toList();

  /// Rows that were not saved: what the user may need to add by hand.
  int get notSaved => count(ImportRowKind.skipped) + count(ImportRowKind.alreadySaved);

  ImportReport markResolved(int rowNumber) => ImportReport(
        batchId: batchId,
        added: added,
        updated: updated,
        sourceName: sourceName,
        headers: headers,
        mapping: mapping,
        entries: entries,
        resolved: {...resolved, rowNumber},
      );

  /// Column index of the Aadhaar column, if the sheet had one.
  int get _aadhaarColumn => mapping.indexOf(fieldId(ImportField.aadhaar));

  /// The row's original cells as (heading, value), Aadhaar masked.
  List<(String, String)> sourceOf(ImportReportEntry e) {
    final cells = e.row.source;
    return [
      for (var i = 0; i < headers.length; i++)
        (
          headers[i].trim().isEmpty ? 'Column ${i + 1}' : headers[i],
          i < cells.length ? (i == _aadhaarColumn ? maskAadhaarCell(cells[i]) : cells[i]) : '',
        ),
    ];
  }

  /// Rows for the "skipped rows" Excel/CSV: Excel row, status, reason and
  /// fix, then the original cells (Aadhaar masked).
  ({List<String> header, List<List<String>> rows}) exportTable(
    Iterable<ImportReportEntry> list, {
    required String Function(ImportRowKind kind) kindLabel,
    required String Function(RowIssue issue) issueLabel,
    required String Function(RowIssueCode code) fixLabel,
    required List<String> leadingHeaders,
  }) =>
      (
        header: [...leadingHeaders, ...headers],
        rows: [
          for (final e in list)
            [
              '${e.rowNumber}',
              kindLabel(e.kind),
              e.problems.map(issueLabel).join('; '),
              e.problems.map((i) => fixLabel(i.code)).toSet().join(' '),
              for (final (_, value) in sourceOf(e)) value,
            ],
        ],
      );
}

/// "XXXX XXXX 7881" for a cell holding an Aadhaar number; other text as
/// it was, but never more than the last four digits.
String maskAadhaarCell(String cell) {
  final digits = cell.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return cell.trim().isEmpty ? '' : 'XXXX';
  return digits.length >= 4 ? Aadhaar.mask(digits.substring(digits.length - 4)) : 'XXXX';
}
