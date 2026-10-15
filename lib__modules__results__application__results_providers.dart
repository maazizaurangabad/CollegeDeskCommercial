import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/reporting/report_dataset.dart';
import '../../students/application/students_providers.dart';
import '../data/result_repository.dart';
import '../domain/result_models.dart';
import 'mark_sheet_pdf.dart';

final resultRepositoryProvider = Provider<ResultRepository>(
  (ref) => ResultRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(sessionProvider),
    ref.watch(appSettingsRepositoryProvider),
    ref.watch(studentRepositoryProvider),
  ),
);

/// Bumped after marks, subjects, exams or rules change.
final resultsRevisionProvider = StateProvider<int>((ref) => 0);

String resultStatusLabel(AppLocalizations l10n, ResultStatus s) => switch (s) {
      ResultStatus.passed => l10n.resPassed,
      ResultStatus.failed => l10n.resFailed,
      ResultStatus.atkt => l10n.resAtkt,
      ResultStatus.incomplete => l10n.resIncomplete,
    };

String resultClassLabel(AppLocalizations l10n, ResultClass c) => switch (c) {
      ResultClass.distinction => l10n.resDistinction,
      ResultClass.first => l10n.resFirstClass,
      ResultClass.second => l10n.resSecondClass,
      ResultClass.pass => l10n.resPassClass,
    };

String resultErrorMessage(AppLocalizations l10n, Object e) {
  if (e is! ResultException) return l10n.saveFailed;
  return switch (e.issue) {
    ResultIssue.emptyName => l10n.feeErrEmptyName,
    ResultIssue.duplicate => l10n.resErrDuplicate,
    ResultIssue.inUse => l10n.resErrInUse,
    ResultIssue.overMax => l10n.resErrOverMax(e.detail ?? ''),
    ResultIssue.badGrade => l10n.resErrBadValue(e.detail ?? ''),
    ResultIssue.notFound => l10n.issueNotFound,
  };
}

/// The class result sheet, laid out like the college's own: Sr, G.R. No,
/// name, one column per subject (or subject choice), total, %, grade
/// subjects, result. Rank and class are optional extra columns.
ReportDataset resultSheetDataset(
  AppLocalizations l10n, {
  required String title,
  required String classLabel,
  required String yearLabel,
  required List<SubjectColumn> columns,
  required List<StudentResult> results,
  required ResultRules rules,
  bool showRank = false,
  bool showClass = false,
}) {
  final marksCols = columns.where((c) => !c.isGrade).toList();
  final gradeCols = columns.where((c) => c.isGrade).toList();
  final maxTotal = results.isEmpty
      ? marksCols.fold(0, (a, c) => a + c.subjects.first.maxMarks)
      : results.map((r) => r.maxTotal).reduce((a, b) => a > b ? a : b);
  const firstData = 3;
  return ReportDataset(
    title: title,
    subtitle: ['$classLabel · $yearLabel'],
    fileName: 'result-${classLabel.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
    landscape: true,
    fontSize: 9,
    zebra: true,
    columns: [
      ReportColumn(l10n.reportSr, width: 24, align: ReportAlign.center, type: ReportColumnType.number),
      ReportColumn(l10n.resColGr, width: 40, align: ReportAlign.center),
      ReportColumn(l10n.resColName, flex: 4),
      for (final c in marksCols) ReportColumn(c.name, width: c.isChoice ? 52 : 44, align: ReportAlign.center, type: ReportColumnType.number),
      ReportColumn(l10n.resColTotal(maxTotal), width: 46, align: ReportAlign.center, type: ReportColumnType.number),
      ReportColumn(l10n.resColPercent, width: 36, align: ReportAlign.center, type: ReportColumnType.number),
      for (final c in gradeCols) ReportColumn(l10n.resColGrade(c.name), width: 46, align: ReportAlign.center),
      if (showClass) ReportColumn(l10n.resColClass, width: 64),
      if (showRank) ReportColumn(l10n.resColRank, width: 32, align: ReportAlign.center, type: ReportColumnType.number),
      ReportColumn(l10n.resColResult, width: 58, align: ReportAlign.center),
    ],
    rows: [
      for (var i = 0; i < results.length; i++)
        ReportRow(
          [
            '${i + 1}',
            results[i].grNumber ?? '',
            results[i].name,
            for (final c in marksCols) results[i].columns[c.name]?.text ?? '-',
            results[i].status == ResultStatus.incomplete && results[i].total == 0 ? '-' : '${results[i].total}',
            results[i].maxTotal == 0 ? '-' : rules.percentText(results[i].percent),
            for (final c in gradeCols) results[i].columns[c.name]?.text ?? '-',
            if (showClass) results[i].resultClass == null ? '' : resultClassLabel(l10n, results[i].resultClass!),
            if (showRank) results[i].rank?.toString() ?? '',
            resultStatusLabel(l10n, results[i].status).toUpperCase(),
          ],
          highlight: results[i].status == ResultStatus.failed,
          textColors: {
            for (var k = 0; k < marksCols.length; k++)
              if (results[i].columns[marksCols[k].name]?.passed == false) firstData + k: 0xFFC62828,
          },
        ),
    ],
    notes: [
      l10n.resSummaryLine(
        results.length,
        results.where((r) => r.status == ResultStatus.passed).length,
        results.where((r) => r.status == ResultStatus.failed).length,
        results.where((r) => r.status == ResultStatus.atkt).length,
      ),
    ],
    signatures: [l10n.reportClassTeacher, l10n.resPrincipal],
  );
}

/// Subject-wise analysis of a class result: appeared, passed, failed, pass %,
/// highest and average; toppers and class counts in the notes.
ReportDataset resultAnalysisDataset(
  AppLocalizations l10n, {
  required String title,
  required String classLabel,
  required String yearLabel,
  required List<SubjectColumn> columns,
  required List<StudentResult> results,
  required ResultRules rules,
}) {
  final rows = <ReportRow>[];
  final marksCols = columns.where((c) => !c.isGrade).toList();
  for (var i = 0; i < marksCols.length; i++) {
    final entries = [
      for (final r in results)
        if (r.columns[marksCols[i].name] case final c? when !c.missing && c.obtained != null) c,
    ];
    final passed = entries.where((c) => c.passed).length;
    final best = entries.isEmpty ? 0 : entries.map((c) => c.obtained!).reduce((a, b) => a > b ? a : b);
    final avg = entries.isEmpty ? 0.0 : entries.map((c) => c.obtained!).reduce((a, b) => a + b) / entries.length;
    rows.add(ReportRow([
      '${i + 1}',
      marksCols[i].name,
      '${entries.length}',
      '$passed',
      '${entries.length - passed}',
      entries.isEmpty ? '-' : (passed * 100 / entries.length).toStringAsFixed(1),
      '$best',
      avg.toStringAsFixed(1),
    ]));
  }
  final done = results.where((r) => r.status != ResultStatus.incomplete).toList();
  final passed = done.where((r) => r.status == ResultStatus.passed).length;
  rows.add(ReportRow([
    '',
    l10n.resOverall,
    '${done.length}',
    '$passed',
    '${done.where((r) => r.status == ResultStatus.failed).length}',
    done.isEmpty ? '-' : (passed * 100 / done.length).toStringAsFixed(1),
    '',
    '',
  ], kind: ReportRowKind.total));
  final toppers = results.where((r) => r.rank != null && r.rank! <= 3).toList()..sort((a, b) => a.rank!.compareTo(b.rank!));
  int count(ResultClass c) => results.where((r) => r.resultClass == c).length;
  return ReportDataset(
    title: l10n.resAnalysisTitle(title),
    subtitle: ['$classLabel · $yearLabel'],
    fileName: 'result-analysis-${classLabel.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
    columns: [
      ReportColumn(l10n.reportSr, width: 26, align: ReportAlign.center, type: ReportColumnType.number),
      ReportColumn(l10n.resChooseColumn, flex: 3),
      ReportColumn(l10n.resAppeared, width: 60, align: ReportAlign.center, type: ReportColumnType.number),
      ReportColumn(l10n.resPassed, width: 56, align: ReportAlign.center, type: ReportColumnType.number),
      ReportColumn(l10n.resFailed, width: 56, align: ReportAlign.center, type: ReportColumnType.number),
      ReportColumn(l10n.resPassPercent, width: 56, align: ReportAlign.center, type: ReportColumnType.number),
      ReportColumn(l10n.resHighest, width: 56, align: ReportAlign.center, type: ReportColumnType.number),
      ReportColumn(l10n.resAverage, width: 56, align: ReportAlign.center, type: ReportColumnType.number),
    ],
    rows: rows,
    notes: [
      if (toppers.isNotEmpty)
        '${l10n.resToppers}: ${[for (final t in toppers) '${t.rank}. ${t.name} (${t.total}, ${rules.percentText(t.percent)}%)'].join('   ')}',
      '${l10n.resDistinction}: ${count(ResultClass.distinction)} · ${l10n.resFirstClass}: ${count(ResultClass.first)} · '
          '${l10n.resSecondClass}: ${count(ResultClass.second)} · ${l10n.resPassClass}: ${count(ResultClass.pass)} · '
          '${l10n.resAtkt}: ${results.where((r) => r.status == ResultStatus.atkt).length}',
    ],
  );
}

MarkSheetWords markSheetWords(AppLocalizations l10n) => MarkSheetWords(
      title: l10n.resMarkSheetTitle,
      name: l10n.resColName,
      gr: l10n.resColGr,
      roll: l10n.sortRoll,
      className: l10n.resColClass,
      year: l10n.academicYearShort,
      subject: l10n.resChooseColumn,
      max: l10n.resMaxShort,
      pass: l10n.resPassShort,
      obtained: l10n.resObtained,
      remark: l10n.resRemark,
      total: l10n.reportTotal,
      percentage: l10n.resColPercent,
      resultClass: l10n.resColClass,
      rank: l10n.resColRank,
      result: l10n.resColResult,
      gradeSubjects: l10n.resGradeSubjects,
      classTeacher: l10n.reportClassTeacher,
      principal: l10n.resPrincipal,
      parent: l10n.resParentSign,
      statusLabel: (s) => resultStatusLabel(l10n, s),
      classLabel: (c) => resultClassLabel(l10n, c),
    );
