import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../platform/modules/module_descriptor.dart';
import 'presentation/attendance_register_screen.dart';
import 'presentation/attendance_screen.dart';

final attendanceModule = ModuleDescriptor(
  id: 'attendance',
  title: (l10n) => l10n.navAttendance,
  icon: Icons.fact_check_outlined,
  selectedIcon: Icons.fact_check,
  route: '/attendance',
  navOrder: 20,
  version: '0.7.0',
  dependsOn: const ['students'],
  requiredPermissions: const {'attendance.mark'},
  builder: (_) => const AttendanceScreen(),
  subRoutes: [
    GoRoute(
      path: 'register',
      pageBuilder: (context, state) {
        final back = state.uri.queryParameters['back'];
        return NoTransitionPage(
          key: ValueKey('register-${state.uri.query}'),
          child: AttendanceRegisterScreen(
            initialDivisionId: state.uri.queryParameters['division'],
            // Only a return to a student's profile is allowed here.
            backTo: back != null && back.startsWith('/students/') ? back : null,
          ),
        );
      },
    ),
  ],
);
