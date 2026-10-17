import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/staff/staff_providers.dart';
import '../../../platform/reporting/report_output.dart';
import '../../reports/application/reports_providers.dart';
import '../../students/application/students_providers.dart';
import '../data/fee_repository.dart';
import '../domain/fee_models.dart';
import 'fee_receipt_pdf.dart';
import 'fee_reports.dart';

final feeRepositoryProvider = Provider<FeeRepository>(
  (ref) => FeeRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(sessionProvider),
    ref.watch(appSettingsRepositoryProvider),
    ref.watch(studentRepositoryProvider),
  ),
);

/// Bumped after a payment, cancellation or setup change.
final feesRevisionProvider = StateProvider<int>((ref) => 0);

final feeHeadsProvider = FutureProvider<List<FeeHead>>((ref) {
  ref.watch(feesRevisionProvider);
  return ref.watch(feeRepositoryProvider).heads();
});

/// Today's collection, for the Fees screen (and the dashboard later).
final feesTodayProvider = FutureProvider<({int total, int count, Map<PaymentMode, int> byMode})>((ref) {
  ref.watch(feesRevisionProvider);
  return ref.watch(feeRepositoryProvider).collectedOn(DateTime.now());
});

String paymentModeLabel(AppLocalizations l10n, PaymentMode m) => switch (m) {
      PaymentMode.cash => l10n.feeModeCash,
      PaymentMode.upi => l10n.feeModeUpi,
      PaymentMode.cheque => l10n.feeModeCheque,
      PaymentMode.bank => l10n.feeModeBank,
    };

/// "₹ 1,25,000" for screens (receipts print "Rs.").
String rupees(int amount) => '₹${Rupees.format(amount)}';

String feeErrorMessage(AppLocalizations l10n, Object error) {
  if (error is! FeeException) return l10n.saveFailed;
  return switch (error.issue) {
    FeeIssue.emptyName => l10n.feeErrEmptyName,
    FeeIssue.duplicateName => l10n.feeErrDuplicateName,
    FeeIssue.headInUse => l10n.feeErrHeadInUse,
    FeeIssue.noAmount => l10n.feeErrNoAmount,
    FeeIssue.negativeAmount => l10n.feeErrNegative,
    FeeIssue.noStudentYear => l10n.feeErrNoYear,
    FeeIssue.notFound => l10n.issueNotFound,
    FeeIssue.futureDate => l10n.feeErrFutureDate,
    FeeIssue.noReason => l10n.feeErrNoReason,
  };
}

Future<Uint8List> feeReceiptPdf(WidgetRef ref, AppLocalizations l10n, FeeReceiptRecord r, {bool officeCopy = true}) async {
  final names = await ref.read(staffNamesProvider.future);
  return FeeReceiptPdf.build(
    r: r,
    head: await reportLetterhead(ref),
    fonts: await ReportOutput.fonts(),
    modeLabel: paymentModeLabel(l10n, r.mode),
    officeCopy: officeCopy,
    issuedBy: userDisplayName(names, r.createdBy, adminName: l10n.staffAdminName),
  );
}

FeeReports feeReports(WidgetRef ref, AppLocalizations l10n) =>
    FeeReports(l10n, ref.read(feeRepositoryProvider), modeLabel: (m) => paymentModeLabel(l10n, m));
