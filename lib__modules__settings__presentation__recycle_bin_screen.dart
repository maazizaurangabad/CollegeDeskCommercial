import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../students/application/students_providers.dart';
import '../../students/domain/student_models.dart';
import '../../students/presentation/student_labels.dart';
import 'settings_page_header.dart';

/// Students deleted in the last 30 days, with Restore.
class RecycleBinScreen extends ConsumerWidget {
  const RecycleBinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.watch(studentsRevisionProvider);
    return SdPage(
      children: [
        SettingsPageHeader(title: l10n.settingsRecycleBin),
        Text(l10n.studentDeleteMessage, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: SdSpace.lg),
        FutureBuilder<List<StudentListItem>>(
          future: ref.read(studentRepositoryProvider).listRecycleBin(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SdSkeleton(height: 120);
            final items = snapshot.data!;
            if (items.isEmpty) {
              return SdEmptyState(icon: Icons.delete_outline, title: l10n.recycleBinEmpty, message: '');
            }
            return SdCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(indent: SdSpace.lg),
                    ListTile(
                      leading: StudentAvatar(name: items[i].fullName),
                      title: Text(items[i].fullName),
                      subtitle: Text(items[i].displayCode),
                      trailing: SdButton(
                        label: l10n.recycleRestore,
                        variant: SdButtonVariant.secondary,
                        onPressed: () async {
                          await ref.read(studentRepositoryProvider).restore(items[i].id);
                          ref.read(studentsRevisionProvider.notifier).state++;
                          if (context.mounted) SdToast.show(context, l10n.restored);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
