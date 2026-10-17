import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../platform/modules/module_descriptor.dart';
import 'presentation/academic_years_screen.dart';
import 'presentation/attendance_settings_screen.dart';
import 'presentation/backup_screen.dart';
import 'presentation/classes_divisions_screen.dart';
import 'presentation/data_health_screen.dart';
import 'presentation/imports_screen.dart';
import 'presentation/institution_profile_screen.dart';
import 'presentation/modules_settings_screen.dart';
import 'presentation/recycle_bin_screen.dart';
import 'presentation/security_screen.dart';
import 'presentation/student_fields_screen.dart';
import 'presentation/settings_screen.dart';
import 'presentation/staff_roles_screen.dart';
import 'presentation/staff_screen.dart';

final settingsModule = ModuleDescriptor(
  id: 'settings',
  title: (l10n) => l10n.navSettings,
  icon: Icons.settings_outlined,
  selectedIcon: Icons.settings,
  route: '/settings',
  navOrder: 1000,
  isCore: true,
  builder: (_) => const SettingsScreen(),
  subRoutes: [
    GoRoute(
      path: 'modules',
      pageBuilder: (context, state) => const NoTransitionPage(child: ModulesSettingsScreen()),
    ),
    GoRoute(
      path: 'institution',
      pageBuilder: (context, state) => const NoTransitionPage(child: InstitutionProfileScreen()),
    ),
    GoRoute(
      path: 'academic-years',
      pageBuilder: (context, state) => const NoTransitionPage(child: AcademicYearsScreen()),
    ),
    GoRoute(
      path: 'classes',
      pageBuilder: (context, state) => const NoTransitionPage(child: ClassesDivisionsScreen()),
    ),
    GoRoute(
      path: 'student-fields',
      pageBuilder: (context, state) => const NoTransitionPage(child: StudentFieldsScreen()),
    ),
    GoRoute(
      path: 'attendance',
      pageBuilder: (context, state) => const NoTransitionPage(child: AttendanceSettingsScreen()),
    ),
    GoRoute(
      path: 'backup',
      pageBuilder: (context, state) => const NoTransitionPage(child: BackupScreen()),
    ),
    GoRoute(
      path: 'staff',
      pageBuilder: (context, state) => const NoTransitionPage(child: StaffScreen()),
      routes: [
        GoRoute(
          path: 'roles',
          pageBuilder: (context, state) => const NoTransitionPage(child: StaffRolesScreen()),
        ),
      ],
    ),
    GoRoute(
      path: 'security',
      pageBuilder: (context, state) => const NoTransitionPage(child: SecurityScreen()),
    ),
    GoRoute(
      path: 'data-health',
      pageBuilder: (context, state) => const NoTransitionPage(child: DataHealthScreen()),
    ),
    GoRoute(
      path: 'imports',
      pageBuilder: (context, state) => const NoTransitionPage(child: ImportsScreen()),
    ),
    GoRoute(
      path: 'recycle-bin',
      pageBuilder: (context, state) => const NoTransitionPage(child: RecycleBinScreen()),
    ),
  ],
);
