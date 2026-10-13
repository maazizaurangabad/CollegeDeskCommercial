import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/data_health.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/data_providers.dart';
import 'settings_page_header.dart';

class DataHealthScreen extends ConsumerStatefulWidget {
  const DataHealthScreen({super.key});

  @override
  ConsumerState<DataHealthScreen> createState() => _DataHealthScreenState();
}

class _DataHealthScreenState extends ConsumerState<DataHealthScreen> {
  late Future<List<HealthFinding>> _future = _check();

  Future<List<HealthFinding>> _check() => DataHealth.run(
        ref.read(appDatabaseProvider),
        ref.read(sessionProvider).organizationId,
        activeYearId: ref.read(academicControllerProvider).activeYear?.id,
      );

  String _label(AppLocalizations l10n, HealthCheck check) => switch (check) {
        HealthCheck.integrity => l10n.healthIntegrity,
        HealthCheck.orphanEnrollments => l10n.healthOrphans,
        HealthCheck.duplicateRolls => l10n.healthDuplicateRolls,
        HealthCheck.multipleActiveEnrollments => l10n.healthMultipleActive,
        HealthCheck.duplicateIdentifiers => l10n.healthDuplicateIds,
        HealthCheck.unplacedActiveStudents => l10n.healthUnplaced,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sd = SdColors.of(context);
    return SdPage(
      children: [
        SettingsPageHeader(
          title: l10n.settingsDataHealth,
          trailing: SdButton(
            label: l10n.healthRun,
            variant: SdButtonVariant.secondary,
            onPressed: () => setState(() => _future = _check()),
          ),
        ),
        FutureBuilder<List<HealthFinding>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SdSkeleton(height: 240);
            final findings = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (findings.every((f) => f.ok))
                  Padding(
                    padding: const EdgeInsets.only(bottom: SdSpace.lg),
                    child: Text(l10n.healthAllGood, style: Theme.of(context).textTheme.titleMedium),
                  ),
                SdCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < findings.length; i++) ...[
                        if (i > 0) const Divider(indent: SdSpace.lg),
                        ListTile(
                          leading: Icon(
                            findings[i].ok ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                            color: findings[i].ok ? sd.present : sd.leave,
                          ),
                          title: Text(_label(l10n, findings[i].check)),
                          subtitle: findings[i].detail == null ? null : Text(findings[i].detail!),
                          trailing: Text(findings[i].ok ? l10n.healthOk : l10n.healthFound(findings[i].count)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
