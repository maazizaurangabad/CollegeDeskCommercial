import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../platform/modules/module_descriptor.dart';
import 'presentation/report_kinds.dart';
import 'presentation/report_run_screen.dart';
import 'presentation/reports_screen.dart';

final reportsModule = ModuleDescriptor(
  id: 'reports',
  title: (l10n) => l10n.navReports,
  icon: Icons.assessment_outlined,
  selectedIcon: Icons.assessment,
  route: '/reports',
  navOrder: 30,
  version: '0.9.0',
  dependsOn: const ['students'],
  requiredPermissions: const {'reports.view'},
  builder: (_) => const ReportsScreen(),
  subRoutes: [
    GoRoute(
      path: ':kind',
      pageBuilder: (context, state) {
        final kind = ReportKind.values.where((k) => k.name == state.pathParameters['kind']).firstOrNull ?? ReportKind.register;
        return NoTransitionPage(key: ValueKey('report-${kind.name}'), child: ReportRunScreen(kind: kind));
      },
    ),
  ],
);
