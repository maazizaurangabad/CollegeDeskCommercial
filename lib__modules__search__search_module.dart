import 'package:flutter/material.dart';

import '../../platform/modules/module_descriptor.dart';
import 'presentation/search_screen.dart';

/// Global search. Opened from the top bar (or Ctrl + K), not from the menu.
final searchModule = ModuleDescriptor(
  id: 'search',
  title: (l10n) => l10n.search,
  icon: Icons.search,
  selectedIcon: Icons.search,
  route: '/search',
  navOrder: 5,
  isCore: true,
  showInNavigation: false,
  version: '0.8.0',
  builder: (_) => const SearchScreen(),
);
