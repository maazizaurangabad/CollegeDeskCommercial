import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/academic/academic_messages.dart';
import '../../../platform/academic/academic_models.dart';
import '../../../platform/organization/organization_providers.dart';
import 'settings_page_header.dart';

class ClassesDivisionsScreen extends ConsumerWidget {
  const ClassesDivisionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final org = ref.watch(activeOrganizationProvider);
    final snapshot = ref.watch(academicControllerProvider);
    final controller = ref.read(academicControllerProvider.notifier);
    final programLabel = (org.programLabel ?? l10n.defaultProgramLabel).toLowerCase();
    final divisionLabel = (org.divisionLabel ?? l10n.defaultDivisionLabel).toLowerCase();
    final year = snapshot.activeYear;
    String message(Object e) => academicErrorMessage(l10n, e);

    Future<String?> askName(String title, [String initial = '']) => SdDialog.prompt(
          context,
          title: title,
          label: l10n.fieldName,
          confirmLabel: l10n.save,
          cancelLabel: l10n.cancel,
          initial: initial,
        );

    Future<bool> confirmDelete(String name) => SdDialog.confirm(
          context,
          title: l10n.deleteConfirmTitle(name),
          message: l10n.deleteConfirmMessage,
          confirmLabel: l10n.delete,
          cancelLabel: l10n.cancel,
          destructive: true,
        );

    return SdPage(
      children: [
        SettingsPageHeader(
          title: l10n.settingsClassesDivisions,
          trailing: year == null
              ? null
              : SdButton(
                  label: l10n.addThing(programLabel),
                  icon: Icons.add,
                  onPressed: () async {
                    final name = await askName(l10n.addThing(programLabel));
                    if (name == null || !context.mounted) return;
                    await runWithFeedback(context, () => controller.addProgram(name), message);
                  },
                ),
        ),
        if (year == null)
          SdEmptyState(icon: Icons.calendar_month_outlined, title: l10n.yearsEmpty, message: l10n.classesNoYear)
        else ...[
          Text(l10n.classesForYear(year.label), style: theme.textTheme.bodySmall),
          const SizedBox(height: SdSpace.md),
          if (snapshot.programs.isEmpty)
            SdEmptyState(icon: Icons.account_tree_outlined, title: l10n.classesEmpty, message: l10n.templateEditLater),
          for (final program in snapshot.programs) ...[
            _ProgramCard(
              program: program,
              divisions: snapshot.divisionsOf(program.id),
              divisionLabel: divisionLabel,
              isFirst: program == snapshot.programs.first,
              isLast: program == snapshot.programs.last,
              onMenu: (choice) async {
                switch (choice) {
                  case 'rename':
                    final name = await askName(l10n.rename, program.name);
                    if (name != null && context.mounted) {
                      await runWithFeedback(context, () => controller.renameProgram(program.id, name), message);
                    }
                  case 'up':
                    await runWithFeedback(context, () => controller.moveProgram(program.id, up: true), message);
                  case 'down':
                    await runWithFeedback(context, () => controller.moveProgram(program.id, up: false), message);
                  case 'delete':
                    if (await confirmDelete(program.name) && context.mounted) {
                      await runWithFeedback(context, () => controller.deleteProgram(program.id), message);
                    }
                }
              },
              onAddDivision: () async {
                final name = await askName(l10n.addThing(divisionLabel));
                if (name != null && context.mounted) {
                  await runWithFeedback(context, () => controller.addDivision(program.id, name), message);
                }
              },
              onDivisionTap: (division) async {
                final choice = await SdSheet.show<String>(
                  context,
                  title: '${program.name} ${division.name}',
                  builder: (sheet) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: Text(l10n.rename),
                        onTap: () => Navigator.of(sheet).pop('rename'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(l10n.delete),
                        onTap: () => Navigator.of(sheet).pop('delete'),
                      ),
                    ],
                  ),
                );
                if (!context.mounted) return;
                if (choice == 'rename') {
                  final name = await askName(l10n.rename, division.name);
                  if (name != null && context.mounted) {
                    await runWithFeedback(context, () => controller.renameDivision(division.id, name), message);
                  }
                } else if (choice == 'delete') {
                  if (await confirmDelete('${program.name} ${division.name}') && context.mounted) {
                    await runWithFeedback(context, () => controller.deleteDivision(division.id), message);
                  }
                }
              },
            ),
            const SizedBox(height: SdSpace.md),
          ],
        ],
      ],
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({
    required this.program,
    required this.divisions,
    required this.divisionLabel,
    required this.isFirst,
    required this.isLast,
    required this.onMenu,
    required this.onAddDivision,
    required this.onDivisionTap,
  });

  final Program program;
  final List<Division> divisions;
  final String divisionLabel;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<String> onMenu;
  final VoidCallback onAddDivision;
  final ValueChanged<Division> onDivisionTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(program.name, style: theme.textTheme.titleMedium),
                    if (program.stream != null) Text(program.stream!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: onMenu,
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
                  if (!isFirst) PopupMenuItem(value: 'up', child: Text(l10n.moveUp)),
                  if (!isLast) PopupMenuItem(value: 'down', child: Text(l10n.moveDown)),
                  PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                ],
              ),
            ],
          ),
          const SizedBox(height: SdSpace.md),
          Wrap(
            spacing: SdSpace.sm,
            runSpacing: SdSpace.sm,
            children: [
              for (final d in divisions) ActionChip(label: Text(d.name), onPressed: () => onDivisionTap(d)),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(l10n.addThing(divisionLabel)),
                onPressed: onAddDivision,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
