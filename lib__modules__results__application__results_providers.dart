import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/reporting/report_dataset.dart';
import '../../students/application/students_providers.dart';
import '../data/result_repository.dart';
import '../domain/result_models.dart';

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
