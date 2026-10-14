import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';

enum ReportKind { register, defaulters, absentees, summary, classList, master, certificates }

extension ReportKindText on ReportKind {
  String title(AppLocalizations l10n) => switch (this) {
        ReportKind.register => l10n.reportRegisterTitle,
        ReportKind.defaulters => l10n.reportDefaultersName,
        ReportKind.absentees => l10n.reportAbsenteesTitle,
        ReportKind.summary => l10n.reportSummaryTitle,
        ReportKind.classList => l10n.reportClassListTitle,
        ReportKind.master => l10n.reportMasterTitle,
        ReportKind.certificates => l10n.certRegisterReport,
      };

  String description(AppLocalizations l10n) => switch (this) {
        ReportKind.register => l10n.reportRegisterDesc,
        ReportKind.defaulters => l10n.reportDefaultersDesc,
        ReportKind.absentees => l10n.reportAbsenteesDesc,
        ReportKind.summary => l10n.reportSummaryDesc,
        ReportKind.classList => l10n.reportClassListDesc,
        ReportKind.master => l10n.reportMasterDesc,
        ReportKind.certificates => l10n.certRegisterReportDesc,
      };

  IconData get icon => switch (this) {
        ReportKind.register => Icons.calendar_view_month_outlined,
        ReportKind.defaulters => Icons.trending_down,
        ReportKind.absentees => Icons.person_off_outlined,
        ReportKind.summary => Icons.insights_outlined,
        ReportKind.classList => Icons.format_list_numbered,
        ReportKind.master => Icons.groups_outlined,
        ReportKind.certificates => Icons.workspace_premium_outlined,
      };
}
