import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/reporting/report_output.dart';
import '../../reports/application/reports_providers.dart';
import '../../students/presentation/student_labels.dart';
import '../application/certificates_providers.dart';
import '../domain/certificate_models.dart';
import 'certificate_view_screen.dart';

enum _Period { month, year, all }

/// The outward register: counts per type at a glance, search, the list,
/// and export to Excel or PDF of exactly what is shown.
class CertificatesScreen extends ConsumerStatefulWidget {
  const CertificatesScreen({super.key});

  @override
  ConsumerState<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends ConsumerState<CertificatesScreen> {
  CertificateKind? _kind;
  _Period _period = _Period.year;
  String _query = '';
  bool _busy = false;

  (DateTime?, DateTime?) _range() {
    final now = DateTime.now();
    return switch (_period) {
      _Period.month => (DateTime(now.year, now.month), now),
      _Period.year => (ref.read(academicControllerProvider).activeYear?.startDate, now),
      _Period.all => (null, null),
    };
  }

  bool _inPeriod(CertificateRecord c) {
    final (from, to) = _range();
    final d = DateTime(c.issuedOn.year, c.issuedOn.month, c.issuedOn.day);
    if (from != null && d.isBefore(DateTime(from.year, from.month, from.day))) return false;
    if (to != null && d.isAfter(DateTime(to.year, to.month, to.day))) return false;
    return true;
  }

  Future<void> _export({required bool excel}) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final (from, to) = _range();
      final builders = await reportBuilders(ref, l10n);
      final data = await builders.certificateRegister(from: from, to: to, kind: _kind, query: _query);
      final head = await reportLetterhead(ref);
      final saved = excel
          ? await ReportOutput.saveExcel(data, head, title: l10n.exportExcel)
          : await ReportOutput.savePdf(data, head, title: l10n.reportSavePdf);
      if (saved && mounted) SdToast.show(context, l10n.exported);
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    ref.watch(certificatesRevisionProvider);
    final dates = DateFormat('d MMM y');
    String shortTitle(CertificateKind k) => certificateTitle(l10n, k).split(' (').first;

    return SdPage(
      children: [
        Row(children: [
          Expanded(child: Text(l10n.navCertificates, style: theme.textTheme.headlineSmall)),
          SdButton(label: l10n.certIssue, icon: Icons.add, onPressed: () => context.go('/certificates/new')),
        ]),
        const SizedBox(height: SdSpace.lg),
        Wrap(spacing: SdSpace.sm, children: [
          for (final (p, label) in [
            (_Period.month, l10n.certPeriodMonth),
            (_Period.year, l10n.certPeriodYear),
            (_Period.all, l10n.certPeriodAll),
          ])
            ChoiceChip(label: Text(label), selected: _period == p, onSelected: (_) => setState(() => _period = p)),
        ]),
        const SizedBox(height: SdSpace.lg),
        FutureBuilder<List<CertificateRecord>>(
          future: ref.read(certificateRepositoryProvider).list(limit: 100000),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SdSkeleton(height: 200);
            final inPeriod = snapshot.data!.where(_inPeriod).toList();
            final issued = inPeriod.where((c) => c.status == CertificateStatus.issued).toList();
            final q = _query.toLowerCase();
            final shown = inPeriod.where((c) {
              if (_kind != null && c.kind != _kind) return false;
              if (q.isEmpty) return true;
              return '${c.studentName} ${c.serialLabel} ${c.fields[CertField.grNumber] ?? ''}'.toLowerCase().contains(q);
            }).toList();

            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Counts at a glance; tap one to show only that type.
              LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth < 560 ? 2 : (constraints.maxWidth < 900 ? 3 : 4);
                final width = (constraints.maxWidth - SdSpace.md * (columns - 1)) / columns;
                Widget tile(String label, int count, CertificateKind? kind) => SizedBox(
                      width: width,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(SdRadius.sm),
                        onTap: () => setState(() => _kind = kind),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(SdRadius.sm),
                            border: Border.all(
                              color: _kind == kind ? theme.colorScheme.primary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: SdStatTile(label: label, value: '$count'),
                        ),
                      ),
                    );
                return Wrap(spacing: SdSpace.md, runSpacing: SdSpace.md, children: [
                  tile(l10n.reportTotal, issued.length, null),
                  for (final k in CertificateKind.values) tile(shortTitle(k), issued.where((c) => c.kind == k).length, k),
                ]);
              }),
              const SizedBox(height: SdSpace.lg),
              SdTextField(hint: l10n.certSearch, prefixIcon: Icons.search, onChanged: (v) => setState(() => _query = v.trim())),
              const SizedBox(height: SdSpace.md),
              Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
                SdButton(
                  label: l10n.exportExcel,
                  icon: Icons.table_chart_outlined,
                  variant: SdButtonVariant.secondary,
                  onPressed: _busy || shown.isEmpty ? null : () => _export(excel: true),
                ),
                SdButton(
                  label: l10n.reportSavePdf,
                  icon: Icons.picture_as_pdf_outlined,
                  variant: SdButtonVariant.secondary,
                  onPressed: _busy || shown.isEmpty ? null : () => _export(excel: false),
                ),
              ]),
              const SizedBox(height: SdSpace.lg),
              if (shown.isEmpty)
                SdEmptyState(
                  icon: Icons.workspace_premium_outlined,
                  title: l10n.certRegisterEmpty,
                  message: '',
                  action: snapshot.data!.isEmpty
                      ? SdButton(label: l10n.certIssue, onPressed: () => context.go('/certificates/new'))
                      : null,
                )
              else
                SdSection(
                  title: '${l10n.certRegister} (${shown.length})',
                  child: SdCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < shown.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.workspace_premium_outlined),
                          title: Text(shown[i].studentName),
                          subtitle: Text([
                            shown[i].serialLabel,
                            shortTitle(shown[i].kind),
                            dates.format(shown[i].issuedOn),
                            if ((shown[i].fields[CertField.purpose] ?? '').isNotEmpty) shown[i].fields[CertField.purpose]!,
                            if (shown[i].printCount > 1) l10n.certPrintCount(shown[i].printCount),
                          ].join(' · ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (shown[i].status == CertificateStatus.cancelled)
                              StatusPill(text: l10n.certCancelled, color: sd.absent)
                            else if (shown[i].isDuplicate)
                              StatusPill(text: l10n.certDuplicate, color: sd.leave),
                            IconButton(
                              tooltip: l10n.certView,
                              icon: const Icon(Icons.visibility_outlined),
                              onPressed: () => openCertificateView(context, shown[i].id),
                            ),
                          ]),
                          onTap: () => openCertificateView(context, shown[i].id),
                        ),
                      ],
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ],
    );
  }
}
