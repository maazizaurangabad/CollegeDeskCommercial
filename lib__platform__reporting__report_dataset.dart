import 'package:flutter/foundation.dart';

enum ReportAlign { left, center, right }

/// A report column. Fixed columns have a [width] in points (1/72 inch);
/// flexible ones share the rest of the line by [flex].
@immutable
class ReportColumn {
  const ReportColumn(this.label, {this.width, this.flex, this.align = ReportAlign.left});

  final String label;
  final double? width;
  final double? flex;
  final ReportAlign align;
}

enum ReportRowKind { data, group, total }

@immutable
class ReportRow {
  const ReportRow(this.cells, {this.kind = ReportRowKind.data, this.highlight = false, this.textColors = const {}})
      : groupTitle = null;

  /// A heading row inside the table, e.g. a class name.
  const ReportRow.group(String title)
      : cells = const [],
        kind = ReportRowKind.group,
        highlight = false,
        textColors = const {},
        groupTitle = title;

  final List<String> cells;
  final ReportRowKind kind;

  /// Drawn with a warning tint, e.g. below 75%.
  final bool highlight;

  /// column index -> ARGB colour for that cell's text.
  final Map<int, int> textColors;
  final String? groupTitle;
}

/// Everything a report shows, independent of where it is shown:
/// on screen, as PDF, Excel or CSV. Modules build these; one engine draws them.
@immutable
class ReportDataset {
  const ReportDataset({
    required this.title,
    required this.columns,
    required this.rows,
    required this.fileName,
    this.subtitle = const [],
    this.landscape = false,
    this.notes = const [],
    this.signatures = const [],
    this.shadedColumns = const {},
    this.fontSize = 9,
  });

  final String title;

  /// Filter lines under the title, e.g. "11th Science A · October 2026".
  final List<String> subtitle;
  final List<ReportColumn> columns;
  final List<ReportRow> rows;

  /// File name without extension.
  final String fileName;
  final bool landscape;

  /// Lines printed after the table (legends, totals).
  final List<String> notes;

  /// Signature captions at the bottom of the last page.
  final List<String> signatures;

  /// Columns drawn with a grey background (e.g. Sundays).
  final Set<int> shadedColumns;
  final double fontSize;

  int get dataRowCount => rows.where((r) => r.kind == ReportRowKind.data).length;

  /// Header + rows as plain text, for Excel and CSV.
  List<List<String>> tableForExport() => [
        for (final r in rows)
          if (r.kind == ReportRowKind.group) [r.groupTitle ?? ''] else r.cells,
      ];
}
