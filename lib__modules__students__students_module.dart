import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../platform/modules/module_descriptor.dart';
import 'presentation/import_report_screen.dart';
import 'presentation/photo_import_screen.dart';
import 'presentation/student_form_screen.dart';
import 'presentation/student_import_screen.dart';
import 'presentation/student_profile_screen.dart';
import 'presentation/students_screen.dart';

final studentsModule = ModuleDescriptor(
  id: 'students',
  title: (l10n) => l10n.navStudents,
  icon: Icons.people_alt_outlined,
  selectedIcon: Icons.people_alt,
  route: '/students',
  navOrder: 10,
  version: '0.5.0',
  requiredPermissions: const {'students.view'},
  builder: (_) => const StudentsScreen(),
  subRoutes: [
    GoRoute(
      path: 'import',
      pageBuilder: (context, state) => const NoTransitionPage(child: StudentImportScreen()),
    ),
    GoRoute(
      path: 'import-report',
      pageBuilder: (context, state) => const NoTransitionPage(child: ImportReportScreen()),
    ),
    GoRoute(
      path: 'import-photos',
      pageBuilder: (context, state) => const NoTransitionPage(child: PhotoImportScreen()),
    ),
    GoRoute(
      path: 'new',
      pageBuilder: (context, state) => NoTransitionPage(
        key: ValueKey('student-new-${state.uri.query}'),
        child: StudentFormScreen(fromImport: state.uri.queryParameters['fromImport'] == '1'),
      ),
    ),
    GoRoute(
      path: ':id',
      pageBuilder: (context, state) => NoTransitionPage(
        key: ValueKey('student-${state.pathParameters['id']}'),
        child: StudentProfileScreen(studentId: state.pathParameters['id']!),
      ),
      routes: [
        GoRoute(
          path: 'edit',
          pageBuilder: (context, state) => NoTransitionPage(
            key: ValueKey('student-edit-${state.pathParameters['id']}'),
            child: StudentFormScreen(studentId: state.pathParameters['id']!),
          ),
        ),
      ],
    ),
  ],
);
