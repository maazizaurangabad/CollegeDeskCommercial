import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../platform/modules/module_descriptor.dart';
import 'presentation/fee_payment_screen.dart';
import 'presentation/fee_receipt_screen.dart';
import 'presentation/fee_reminders_screen.dart';
import 'presentation/fee_setup_screen.dart';
import 'presentation/fee_structure_screen.dart';
import 'presentation/fee_student_screen.dart';
import 'presentation/fees_screen.dart';

/// Fees: heads, class-wise (and optionally category-wise) structures,
/// concessions, payments and numbered receipts.
final feesModule = ModuleDescriptor(
  id: 'fees',
  title: (l10n) => l10n.navFees,
  icon: Icons.currency_rupee_outlined,
  selectedIcon: Icons.currency_rupee,
  route: '/fees',
  navOrder: 24,
  version: '1.0.0',
  dependsOn: const ['students'],
  requiredPermissions: const {'fees.collect'},
  builder: (_) => const FeesScreen(),
  subRoutes: [
    GoRoute(
      path: 'pay',
      pageBuilder: (context, state) => NoTransitionPage(
        key: ValueKey('fee-pay-${state.uri.query}'),
        child: FeePaymentScreen(studentId: state.uri.queryParameters['student']),
      ),
    ),
    GoRoute(
      path: 'student/:id',
      pageBuilder: (context, state) => NoTransitionPage(
        key: ValueKey('fee-student-${state.pathParameters['id']}'),
        child: FeeStudentScreen(studentId: state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: 'receipt/:id',
      pageBuilder: (context, state) => NoTransitionPage(
        key: ValueKey('fee-receipt-${state.pathParameters['id']}'),
        child: FeeReceiptScreen(id: state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: 'reminders',
      pageBuilder: (context, state) => const NoTransitionPage(child: FeeRemindersScreen()),
    ),
    GoRoute(
      path: 'setup',
      pageBuilder: (context, state) => const NoTransitionPage(child: FeeSetupScreen()),
    ),
    GoRoute(
      path: 'structure',
      pageBuilder: (context, state) => NoTransitionPage(
        key: ValueKey('fee-structure-${state.uri.query}'),
        child: FeeStructureScreen(
          programId: state.uri.queryParameters['program'] ?? '',
          category: state.uri.queryParameters['category'],
        ),
      ),
    ),
  ],
);
