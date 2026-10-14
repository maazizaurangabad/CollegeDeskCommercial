import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../platform/modules/module_descriptor.dart';
import 'domain/certificate_models.dart';
import 'presentation/certificate_issue_screen.dart';
import 'presentation/certificate_view_screen.dart';
import 'presentation/certificates_screen.dart';

final certificatesModule = ModuleDescriptor(
  id: 'certificates',
  title: (l10n) => l10n.navCertificates,
  icon: Icons.workspace_premium_outlined,
  selectedIcon: Icons.workspace_premium,
  route: '/certificates',
  navOrder: 25,
  version: '1.0.0',
  dependsOn: const ['students'],
  requiredPermissions: const {'certificates.issue'},
  builder: (_) => const CertificatesScreen(),
  subRoutes: [
    GoRoute(
      path: 'new',
      pageBuilder: (context, state) => NoTransitionPage(
        key: ValueKey('cert-new-${state.uri.query}'),
        child: CertificateIssueScreen(
          studentId: state.uri.queryParameters['student'],
          kind: CertificateKind.byName(state.uri.queryParameters['kind'] ?? ''),
        ),
      ),
    ),
    GoRoute(
      path: 'view/:id',
      pageBuilder: (context, state) => NoTransitionPage(
        key: ValueKey('cert-${state.pathParameters['id']}'),
        child: CertificateViewScreen(id: state.pathParameters['id']!),
      ),
    ),
  ],
);
