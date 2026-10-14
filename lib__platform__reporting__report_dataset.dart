import 'package:flutter/foundation.dart';

enum ReportAlign { left, center, right }

/// How a column is written to Excel: text, a real number, or a real date
/// (so Excel sorts and filters it properly).
enum ReportColumnType { text, number, date }

/// A report column. Fixed columns have a [width] in points (1/72 inch);
/// flexible ones share the rest of the line by [flex].
@immutable
class ReportColumn {
  const ReportColumn(
    this.label, {
    this.width,
    this.flex,
    this.align = ReportAlign.left,
    this.type = ReportColumnType.text,
  });

  final String label;
  final double? width;
  final double? flex;
  final ReportAlign align;
  final ReportColumnType type;
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

/// Labels for the count lines, e.g. "Total 120 · Boys 64 · Girls 56".
@immutable
class ReportCountLabels {
  const ReportCountLabels({required this.total, required this.byValue});

  final String total;

  /// cell value -> label, e.g. {"Male": "Boys", "Female": "Girls"}.
  final Map<String, String> byValue;
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
    this.filterColumns = const {},
    this.countColumn,
    this.countLabels,
    this.groupLabel = 'Group',
    this.zebra = false,
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

  /// Columns offered as filters on screen (e.g. gender, category).
  final Set<int> filterColumns;

  /// Column counted in the summary lines (usually gender).
  final int? countColumn;
  final ReportCountLabels? countLabels;

  /// Heading of the extra first column Excel gets when rows are grouped.
  final String groupLabel;

  /// Alternate row shading, for long name lists.
  final bool zebra;

  int get dataRowCount => rows.where((r) => r.kind == ReportRowKind.data).length;

  bool get hasGroups => rows.any((r) => r.kind == ReportRowKind.group);

  ReportDataset copyWith({List<ReportRow>? rows, List<String>? notes, List<String>? subtitle}) => ReportDataset(
        title: title,
        columns: columns,
        rows: rows ?? this.rows,
        fileName: fileName,
        subtitle: subtitle ?? this.subtitle,
        landscape: landscape,
        notes: notes ?? this.notes,
        signatures: signatures,
        shadedColumns: shadedColumns,
        fontSize: fontSize,
        filterColumns: filterColumns,
        countColumn: countColumn,
        countLabels: countLabels,
        groupLabel: groupLabel,
        zebra: zebra,
      );

  /// Distinct values of a column, for filter choices.
  List<String> valuesOf(int column) {
    final values = <String>{
      for (final r in rows)
        if (r.kind == ReportRowKind.data && column < r.cells.length && r.cells[column].isNotEmpty) r.cells[column],
    }.toList()
      ..sort();
    return values;
  }

  /// The same report with filters and sorting applied. Groups stay, are
  /// sorted inside, and disappear when empty. Count lines are recalculated.
  ReportDataset arranged({Map<int, String> filters = const {}, int? sortColumn, bool ascending = true}) {
    final groups = <(ReportRow?, List<ReportRow>)>[];
    for (final r in rows) {
      if (r.kind == ReportRowKind.group) {
        groups.add((r, []));
      } else {
        if (groups.isEmpty) groups.add((null, []));
        groups.last.$2.add(r);
      }
    }
    int compare(ReportRow a, ReportRow b) {
      final col = sortColumn!;
      final x = col < a.cells.length ? a.cells[col] : '';
      final y = col < b.cells.length ? b.cells[col] : '';
      final nx = double.tryParse(x.replaceAll('%', ''));
      final ny = double.tryParse(y.replaceAll('%', ''));
      final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.toLowerCase().compareTo(y.toLowerCase());
      return ascending ? c : -c;
    }

    final out = <ReportRow>[];
    for (final (head, data) in groups) {
      var list = data
          .where((r) =>
              r.kind != ReportRowKind.data ||
              filters.entries.every((f) => f.key < r.cells.length && r.cells[f.key] == f.value))
          .toList();
      if (sortColumn != null) {
        final dataOnly = list.where((r) => r.kind == ReportRowKind.data).toList()..sort(compare);
        list = [...dataOnly, ...list.where((r) => r.kind != ReportRowKind.data)];
      }
      if (!list.any((r) => r.kind == ReportRowKind.data)) continue;
      if (head != null) out.add(head);
      out.addAll(list);
    }
    return copyWith(rows: out).withCounts();
  }

  /// Adds "(count · Boys · Girls)" to group headings and a total line to the notes.
  ReportDataset withCounts() {
    final labels = countLabels;
    if (labels == null) return this;
    String summary(Iterable<ReportRow> data) {
      final list = data.toList();
      final parts = ['${labels.total} ${list.length}'];
      if (countColumn != null) {
        for (final e in labels.byValue.entries) {
          final n = list.where((r) => countColumn! < r.cells.length && r.cells[countColumn!] == e.key).length;
          if (n > 0) parts.add('${e.value} $n');
        }
      }
      return parts.join(' · ');
    }

    final out = <ReportRow>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r.kind != ReportRowKind.group) {
        out.add(r);
        continue;
      }
      final members = <ReportRow>[];
      for (var j = i + 1; j < rows.length && rows[j].kind != ReportRowKind.group; j++) {
        if (rows[j].kind == ReportRowKind.data) members.add(rows[j]);
      }
      final base = (r.groupTitle ?? '').split('   (').first;
      out.add(ReportRow.group('$base   (${summary(members)})'));
    }
    final data = rows.where((r) => r.kind == ReportRowKind.data);
    final kept = notes.where((n) => !n.startsWith('${labels.total} ')).toList();
    return copyWith(rows: out, notes: [summary(data), ...kept]);
  }

  /// Rows for Excel and CSV: data rows only, with the group (e.g. class)
  /// as an extra first column when the report is grouped.
  ({List<String> header, List<List<String>> rows}) tableForExport() {
    final grouped = hasGroups;
    final header = [if (grouped) groupLabel, for (final c in columns) c.label];
    final out = <List<String>>[];
    String group = '';
    for (final r in rows) {
      if (r.kind == ReportRowKind.group) {
        group = (r.groupTitle ?? '').split('   (').first;
      } else if (r.kind == ReportRowKind.data) {
        out.add([if (grouped) group, ...r.cells]);
      }
    }
    return (header: header, rows: out);
  }

  /// Column types matching [tableForExport]'s columns.
  List<ReportColumnType> exportTypes() => [if (hasGroups) ReportColumnType.text, for (final c in columns) c.type];
}
