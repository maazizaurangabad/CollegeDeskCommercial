import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../platform/modules/module_descriptor.dart';
import 'presentation/message_templates_screen.dart';
import 'presentation/messages_screen.dart';

/// Messages to parents: daily absentee summary, one-tap WhatsApp message to
/// each absent student's parent, and the history of what was sent.
final messagesModule = ModuleDescriptor(
  id: 'messages',
  title: (l10n) => l10n.navMessages,
  icon: Icons.forum_outlined,
  selectedIcon: Icons.forum,
  route: '/messages',
  navOrder: 22,
  version: '1.0.0',
  dependsOn: const ['students', 'attendance'],
  requiredPermissions: const {'messages.send'},
  builder: (_) => const MessagesScreen(),
  subRoutes: [
    GoRoute(
      path: 'templates',
      pageBuilder: (context, state) => NoTransitionPage(
        child: MessageTemplatesScreen(backTo: state.uri.queryParameters['from'] == 'messages' ? '/messages' : '/settings'),
      ),
    ),
  ],
);
