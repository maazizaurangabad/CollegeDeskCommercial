import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../students/presentation/student_labels.dart';
import '../application/certificates_providers.dart';
import '../domain/certificate_models.dart';

/// The register of every certificate issued, with filters by type.
class CertificatesScreen extends ConsumerStatefulWidget {
  const CertificatesScreen({super.key});

  @override
  ConsumerState<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends ConsumerState<CertificatesScreen> {
  CertificateKind? _kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    ref.watch(certificatesRevisionProvider);
    final dates = DateFormat('d MMM y');
    return SdPage(
      children: [
        Row(children: [
          Expanded(child: Text(l10n.navCertificates, style: theme.textTheme.headlineSmall)),
          SdButton(label: l10n.certIssue, icon: Icons.add, onPressed: () => context.go('/certificates/new')),
        ]),
        const SizedBox(height: SdSpace.lg),
        Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
          ChoiceChip(label: Text(l10n.certAllTypes), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
          for (final k in CertificateKind.values)
            ChoiceChip(
              label: Text(certificateTitle(l10n, k).split(' (').first),
              selected: _kind == k,
              onSelected: (_) => setState(() => _kind = k),
            ),
        ]),
        const SizedBox(height: SdSpace.lg),
        FutureBuilder<List<CertificateRecord>>(
          future: ref.read(certificateRepositoryProvider).list(kind: _kind),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SdSkeleton(height: 160);
            final items = snapshot.data!;
            if (items.isEmpty) {
              return SdEmptyState(
                icon: Icons.workspace_premium_outlined,
                title: l10n.certRegisterEmpty,
                message: '',
                action: SdButton(label: l10n.certIssue, onPressed: () => context.go('/certificates/new')),
              );
            }
            return SdSection(
              title: l10n.certRegister,
              child: SdCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title: Text(items[i].studentName),
                      subtitle: Text([
                        items[i].serialLabel,
                        certificateTitle(l10n, items[i].kind).split(' (').first,
                        dates.format(items[i].issuedOn),
                        if (items[i].printCount > 1) l10n.certPrintCount(items[i].printCount),
                      ].join(' · ')),
                      trailing: items[i].status == CertificateStatus.cancelled
                          ? StatusPill(text: l10n.certCancelled, color: sd.absent)
                          : (items[i].isDuplicate
                              ? StatusPill(text: l10n.certDuplicate, color: sd.leave)
                              : const Icon(Icons.chevron_right)),
                      onTap: () => context.go('/certificates/view/${items[i].id}'),
                    ),
                  ],
                ]),
              ),
            );
          },
        ),
      ],
    );
  }
}
