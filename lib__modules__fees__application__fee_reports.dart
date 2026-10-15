import 'package:intl/intl.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/reporting/report_dataset.dart';
import '../data/fee_repository.dart';
import '../domain/fee_models.dart';

/// Fee reports as datasets; the reporting engine shows them and makes
/// PDF and Excel. Money columns are plain numbers so Excel can add them.
class FeeReports {
  FeeReports(this.l10n, this.fees, {required this.modeLabel});

  final AppLocalizations l10n;
  final FeeRepository fees;
  final String Function(PaymentMode mode) modeLabel;

  static final _date = DateFormat('dd/MM/yyyy');

  static String rs(int v) => 'Rs. ${Rupees.format(v)}';

  String _range(DateTime? from, DateTime? to) =>
      (from == null && to == null) ? '' : '${from == null ? '…' : _date.format(from)} – ${to == null ? '…' : _date.format(to)}';

  /// Every receipt in the period, oldest first, with totals by payment mode.
  Future<ReportDataset> dayBook({DateTime? from, DateTime? to}) async {
    final items = (await fees.receipts(from: from, to: to)).reversed.toList();
    final byMode = <PaymentMode, int>{};
    var total = 0, cancelled = 0;
    for (final r in items) {
      if (r.isCancelled) {
        cancelled++;
        continue;
      }
      total += r.total;
      byMode[r.mode] = (byMode[r.mode] ?? 0) + r.total;
    }
    return ReportDataset(
      title: l10n.feeReportDayBook,
      subtitle: [_range(from, to)],
      fileName: 'fee-day-book',
      landscape: true,
      zebra: true,
      columns: [
        ReportColumn(l10n.reportSr, width: 26, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.msgColDate, width: 58, type: ReportColumnType.date),
        ReportColumn(l10n.feeColReceipt, width: 100),
        ReportColumn(l10n.fieldName, flex: 3),
        ReportColumn(l10n.fieldClass, width: 90),
        ReportColumn(l10n.feePaidBy, width: 70),
        ReportColumn(l10n.feeReference, flex: 1.5),
        ReportColumn(l10n.feeAmount, width: 64, align: ReportAlign.right, type: ReportColumnType.number),
        ReportColumn(l10n.studentsFilterStatus, flex: 1.5),
      ],
      rows: [
        for (var i = 0; i < items.length; i++)
          ReportRow(
            [
              '${i + 1}',
              _date.format(items[i].receivedOn),
              items[i].serialLabel,
              items[i].studentName,
              items[i].classLabel,
              modeLabel(items[i].mode),
              items[i].reference ?? '',
              items[i].isCancelled ? '0' : '${items[i].total}',
              items[i].isCancelled ? '${l10n.certCancelled}: ${items[i].cancelReason ?? ''} (${rs(items[i].total)})' : '',
            ],
            highlight: items[i].isCancelled,
          ),
      ],
      notes: [
        [for (final m in PaymentMode.values) if (byMode[m] != null) '${modeLabel(m)} ${rs(byMode[m]!)}'].join(' · '),
        '${l10n.reportTotal}: ${rs(total)}',
        if (cancelled > 0) l10n.feeCancelledCount(cancelled),
      ],
    );
  }

  /// How much each fee head brought in during the period.
  Future<ReportDataset> headWise({DateTime? from, DateTime? to}) async {
    final items = (await fees.receipts(from: from, to: to)).where((r) => !r.isCancelled);
    final heads = await fees.heads();
    final order = [for (final h in heads) h.id];
    final amount = <String, int>{};
    final count = <String, int>{};
    final names = <String, String>{};
    for (final r in items) {
      for (final l in r.lines) {
        amount[l.headId] = (amount[l.headId] ?? 0) + l.amount;
        count[l.headId] = (count[l.headId] ?? 0) + 1;
        names[l.headId] = l.headName;
      }
    }
    final ids = amount.keys.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a), ib = order.indexOf(b);
        return (ia < 0 ? 1 << 20 : ia).compareTo(ib < 0 ? 1 << 20 : ib);
      });
    final total = amount.values.fold(0, (a, b) => a + b);
    final current = {for (final h in heads) h.id: h.name};
    return ReportDataset(
      title: l10n.feeReportHeads,
      subtitle: [_range(from, to)],
      fileName: 'fee-head-wise',
      columns: [
        ReportColumn(l10n.reportSr, width: 26, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.feeHead, flex: 3),
        ReportColumn(l10n.feeColReceipts, width: 70, align: ReportAlign.right, type: ReportColumnType.number),
        ReportColumn(l10n.feeAmount, width: 90, align: ReportAlign.right, type: ReportColumnType.number),
      ],
      rows: [
        for (var i = 0; i < ids.length; i++)
          ReportRow(['${i + 1}', current[ids[i]] ?? names[ids[i]] ?? '', '${count[ids[i]]}', '${amount[ids[i]]}']),
        ReportRow(['', l10n.reportTotal, '', '$total'], kind: ReportRowKind.total),
      ],
      notes: ['${l10n.reportTotal}: ${rs(total)}'],
    );
  }

  /// One line per class: students, due, paid, balance and overdue.
  Future<ReportDataset> classSummary(String academicYearId, String yearLabel) async {
    final all = await fees.balances(academicYearId);
    final classes = <String, List<StudentFeeBalance>>{};
    for (final b in all) {
      (classes[b.classLabel] ??= []).add(b);
    }
    int sum(Iterable<StudentFeeBalance> list, int Function(StudentFeeBalance) f) => list.fold(0, (a, b) => a + f(b));
    final labels = classes.keys.toList()..sort();
    return ReportDataset(
      title: l10n.feeReportClassSummary,
      subtitle: [yearLabel],
      fileName: 'fee-class-summary',
      columns: [
        ReportColumn(l10n.reportSr, width: 26, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.fieldClass, flex: 2),
        ReportColumn(l10n.feeColStudents, width: 56, align: ReportAlign.right, type: ReportColumnType.number),
        ReportColumn(l10n.feeDue, width: 76, align: ReportAlign.right, type: ReportColumnType.number),
        ReportColumn(l10n.feePaid, width: 76, align: ReportAlign.right, type: ReportColumnType.number),
        ReportColumn(l10n.feeBalance, width: 76, align: ReportAlign.right, type: ReportColumnType.number),
        ReportColumn(l10n.feeOverdue, width: 76, align: ReportAlign.right, type: ReportColumnType.number),
      ],
      rows: [
        for (var i = 0; i < labels.length; i++)
          ReportRow([
            '${i + 1}',
            labels[i],
            '${classes[labels[i]]!.length}',
            '${sum(classes[labels[i]]!, (b) => b.due)}',
            '${sum(classes[labels[i]]!, (b) => b.paid)}',
            '${sum(classes[labels[i]]!, (b) => b.balance)}',
            '${sum(classes[labels[i]]!, (b) => b.overdue)}',
          ]),
        ReportRow([
          '',
          l10n.reportTotal,
          '${all.length}',
          '${sum(all, (b) => b.due)}',
          '${sum(all, (b) => b.paid)}',
          '${sum(all, (b) => b.balance)}',
          '${sum(all, (b) => b.overdue)}',
        ], kind: ReportRowKind.total),
      ],
      notes: [l10n.feeBalanceNote],
    );
  }

  /// Students who still owe fees, class by class, with a parent's mobile.
  Future<ReportDataset> defaulters(String academicYearId, String yearLabel, {String? programId, bool overdueOnly = false}) async {
    final list = (await fees.balances(academicYearId))
        .where((b) => programId == null || b.programId == programId)
        .where((b) => overdueOnly ? b.overdue > 0 : b.balance > 0)
        .toList();
    final rows = <ReportRow>[];
    String? current;
    var n = 0;
    for (final b in list) {
      if (b.classLabel != current) {
        current = b.classLabel;
        rows.add(ReportRow.group(b.classLabel));
      }
      n++;
      rows.add(ReportRow([
        '$n',
        b.rollNumber?.toString() ?? '',
        b.name,
        b.category ?? '',
        b.mobile ?? '',
        '${b.due}',
        '${b.paid}',
        '${b.balance}',
        '${b.overdue}',
      ]));
    }
    final balance = list.fold(0, (a, b) => a + b.balance);
    final overdue = list.fold(0, (a, b) => a + b.overdue);
    return ReportDataset(
      title: overdueOnly ? l10n.feeReportOverdue : l10n.feeReportDefaulters,
      subtitle: [yearLabel],
      fileName: overdueOnly ? 'fee-overdue' : 'fee-defaulters',
      landscape: true,
      zebra: true,
      groupLabel: l10n.fieldClass,
      columns: [
        ReportColumn(l10n.reportSr, width: 26, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.feeColRoll, width: 34, align: ReportAlign.center, type: ReportColumnType.number),
        ReportColumn(l10n.fieldName, flex: 3),
        ReportColumn(l10n.feeColCategory, width: 56),
        ReportColumn(l10n.fieldMobile, width: 72),
        ReportColumn(l10n.feeDue, width: 64, align: ReportAlign.right, type: ReportColumnType.number),
        ReportColumn(l10n.feePaid, width: 64, align: ReportAlign.right, type: ReportColumnType.number),
        ReportColumn(l10n.feeBalance, width: 64, align: ReportAlign.right, type: ReportColumnType.number),
        ReportColumn(l10n.feeOverdue, width: 64, align: ReportAlign.right, type: ReportColumnType.number),
      ],
      rows: rows,
      notes: ['${l10n.feeColStudents}: ${list.length} · ${l10n.feeBalance}: ${rs(balance)} · ${l10n.feeOverdue}: ${rs(overdue)}'],
    );
  }
}
