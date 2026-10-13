import 'package:flutter/material.dart';

import '../../platform/modules/module_descriptor.dart';
import 'presentation/dashboard_screen.dart';

final dashboardModule = ModuleDescriptor(
  id: 'dashboard',
  title: (l10n) => l10n.navDashboard,
  icon: Icons.space_dashboard_outlined,
  selectedIcon: Icons.space_dashboard,
  route: '/',
  navOrder: 0,
  isCore: true,
  builder: (_) => const DashboardScreen(),
);
