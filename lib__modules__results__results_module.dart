import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../platform/modules/module_descriptor.dart';
import 'presentation/marks_entry_screen.dart';
import 'presentation/result_messages_screen.dart';
import 'presentation/results_screen.dart';
import 'presentation/results_setup_screen.dart';

/// Results: subjects per class, exams, marks entry, and the class result
/// sheet worked out with the institution's own rules.
final resultsModule = ModuleDescriptor(
  id: 'results',
  title: (l10n) => l10n.navResults,
  icon: Icons.emoji_events_outlined,
  selectedIcon: Icons.emoji_events,
  route: '/results',
  navOrder: 26,
  version: '1.0.0',
  dependsOn: const ['students'],
  requiredPermissions: const {'results.manage'},
  builder: (_) => const ResultsScreen(),
  subRoutes: [
    GoRoute(
      path: 'marks',
      pageBuilder: (context, state) => NoTransitionPage(
        key: ValueKey('marks-${state.uri.query}'),
        child: MarksEntryScreen(
          examId: state.uri.queryParameters['exam'] ?? '',
          divisionId: state.uri.queryParameters['division'] ?? '',
        ),
      ),
    ),
    GoRoute(
      path: 'send',
      pageBuilder: (context, state) => NoTransitionPage(
        key: ValueKey('result-send-${state.uri.query}'),
        child: ResultMessagesScreen(
          divisionId: state.uri.queryParameters['division'] ?? '',
          examKey: state.uri.queryParameters['exam'] ?? 'final',
        ),
      ),
    ),
    GoRoute(
      path: 'setup',
      pageBuilder: (context, state) => const NoTransitionPage(child: ResultsSetupScreen()),
    ),
  ],
);
