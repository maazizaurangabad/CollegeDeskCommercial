import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'report_kinds.dart';

/// The list of available reports.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = <String, List<ReportKind>>{
      l10n.reportGroupAttendance: [ReportKind.register, ReportKind.defaulters, ReportKind.absentees, ReportKind.summary],
      l10n.reportGroupStudents: [ReportKind.classList, ReportKind.master],
    };
    return SdPage(
      children: [
        Text(l10n.navReports, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: SdSpace.xs),
        Text(l10n.reportsIntro, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: SdSpace.xl),
        for (final g in groups.entries) ...[
          SdSection(
            title: g.key,
            child: SdCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < g.value.length; i++) ...[
                  if (i > 0) const Divider(indent: SdSpace.lg),
                  ListTile(
                    leading: Icon(g.value[i].icon),
                    title: Text(g.value[i].title(l10n)),
                    subtitle: Text(g.value[i].description(l10n)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/reports/${g.value[i].name}'),
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: SdSpace.xl),
        ],
      ],
    );
  }
}
