import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../academic/structure_templates.dart';
import '../../organization/institution_seal.dart';
import '../institution_draft.dart';
import '../workspace_actions.dart';
import 'institution_form_fields.dart';

/// Five short steps that create a real institution on this device.
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  static const _stepCount = 5;

  int _step = 0;
  bool _creating = false;
  final _detailsForm = GlobalKey<FormState>();
  final _yearForm = GlobalKey<FormState>();

  late final InstitutionDraft _draft;
  final _name = TextEditingController();
  final _shortName = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _udise = TextEditingController();
  final _board = TextEditingController();
  final _medium = TextEditingController();
  final _yearLabel = TextEditingController();

  @override
  void initState() {
    super.initState();
    final year = InstitutionDraft.defaultYear(DateTime.now());
    _draft = InstitutionDraft(
      yearLabel: year.label,
      yearStart: year.start,
      yearEnd: year.end,
      brandColor: SdPalette.ink,
    );
    _yearLabel.text = year.label;
    _shortName.addListener(() => setState(() {}));
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_name, _shortName, _address, _city, _state, _phone, _email, _website, _udise, _board, _medium, _yearLabel]) {
      c.dispose();
    }
    super.dispose();
  }

  void _collect() {
    _draft
      ..name = _name.text
      ..shortName = _shortName.text
      ..address = _address.text
      ..city = _city.text
      ..state = _state.text
      ..phone = _phone.text
      ..email = _email.text
      ..website = _website.text
      ..udiseCode = _udise.text
      ..board = _board.text
      ..medium = _medium.text
      ..yearLabel = _yearLabel.text;
  }

  Future<void> _next() async {
    if (_step == 0 && !(_detailsForm.currentState?.validate() ?? false)) return;
    if (_step == 2) {
      if (!(_yearForm.currentState?.validate() ?? false)) return;
      if (!_draft.yearEnd.isAfter(_draft.yearStart)) {
        SdToast.show(context, AppLocalizations.of(context).issueEndBeforeStart);
        return;
      }
    }
    _collect();
    if (_step < _stepCount - 1) {
      setState(() => _step++);
      return;
    }
    await _create();
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _creating = true);
    try {
      // On success the whole app reopens on the new institution.
      await ref.read(workspaceActionsProvider).createInstitution(_draft);
    } catch (_) {
      if (mounted) setState(() => _creating = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.createFailed)));
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _draft.yearStart : _draft.yearEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _draft.yearStart = picked;
      } else {
        _draft.yearEnd = picked;
      }
    });
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path != null) setState(() => _draft.logoSourcePath = path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final titles = [
      l10n.setupDetailsTitle,
      l10n.setupBoardTitle,
      l10n.setupYearTitle,
      l10n.setupStructureTitle,
      l10n.setupBrandingTitle,
    ];
    final isLast = _step == _stepCount - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.setupTitle),
        leading: IconButton(
          tooltip: l10n.cancel,
          icon: const Icon(Icons.close),
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: (_step + 1) / _stepCount, minHeight: 3),
            Expanded(
              child: SdPage(
                children: [
                  Text(l10n.setupStepOf(_step + 1, _stepCount), style: theme.textTheme.bodySmall),
                  const SizedBox(height: SdSpace.xs),
                  Text(titles[_step], style: theme.textTheme.headlineSmall),
                  const SizedBox(height: SdSpace.xl),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: _stepBody(l10n),
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(SdSpace.lg),
              child: Row(
                children: [
                  if (_step > 0)
                    SdButton(
                      label: l10n.back,
                      variant: SdButtonVariant.text,
                      onPressed: _creating ? null : () => setState(() => _step--),
                    ),
                  const Spacer(),
                  SdButton(
                    label: isLast ? l10n.createInstitution : l10n.next,
                    icon: isLast ? Icons.check : null,
                    onPressed: _creating ? null : _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(AppLocalizations l10n) {
    switch (_step) {
      case 0:
        return Form(
          key: _detailsForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormFieldRow(controller: _name, label: l10n.fieldName, validator: (v) => requiredText(l10n, v)),
              FormFieldRow(
                controller: _shortName,
                label: l10n.fieldShortName,
                hint: l10n.fieldShortNameHint,
                validator: (v) => requiredText(l10n, v),
              ),
              InstitutionTypeChoice(
                value: _draft.institutionType,
                onChanged: (t) => setState(() => _draft.institutionType = t),
              ),
              FormFieldRow(controller: _address, label: l10n.fieldAddress, maxLines: 2),
              FormFieldRow(controller: _city, label: l10n.fieldCity),
              FormFieldRow(controller: _state, label: l10n.fieldState),
              FormFieldRow(controller: _phone, label: l10n.fieldPhone, keyboardType: TextInputType.phone),
              FormFieldRow(
                controller: _email,
                label: l10n.fieldEmail,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => optionalEmail(l10n, v),
              ),
              FormFieldRow(controller: _website, label: l10n.fieldWebsite, keyboardType: TextInputType.url),
              FormFieldRow(controller: _udise, label: l10n.fieldUdise, keyboardType: TextInputType.number),
            ],
          ),
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormFieldRow(controller: _board, label: l10n.fieldBoard, hint: l10n.fieldBoardHint),
            FormFieldRow(controller: _medium, label: l10n.fieldMedium, hint: l10n.fieldMediumHint),
          ],
        );
      case 2:
        final format = DateFormat('d MMM y');
        return Form(
          key: _yearForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormFieldRow(controller: _yearLabel, label: l10n.fieldYearLabel, validator: (v) => requiredText(l10n, v)),
              SdCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: Text(l10n.fieldYearStart),
                      subtitle: Text(format.format(_draft.yearStart)),
                      onTap: () => _pickDate(start: true),
                    ),
                    const Divider(indent: SdSpace.lg),
                    ListTile(
                      leading: const Icon(Icons.event_available_outlined),
                      title: Text(l10n.fieldYearEnd),
                      subtitle: Text(format.format(_draft.yearEnd)),
                      onTap: () => _pickDate(start: false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 3:
        final options = [
          (StructureTemplate.juniorCollege, l10n.templateJuniorCollege, l10n.templateJuniorCollegeDetail),
          (StructureTemplate.school, l10n.templateSchool, l10n.templateSchoolDetail),
          (StructureTemplate.coaching, l10n.templateCoaching, l10n.templateCoachingDetail),
          (StructureTemplate.blank, l10n.templateBlank, l10n.templateBlankDetail),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SdCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < options.length; i++) ...[
                    if (i > 0) const Divider(indent: SdSpace.lg),
                    ListTile(
                      leading: Icon(
                        options[i].$1 == _draft.template ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: options[i].$1 == _draft.template ? Theme.of(context).colorScheme.primary : null,
                      ),
                      title: Text(options[i].$2),
                      subtitle: Text(options[i].$3),
                      onTap: () => setState(() => _draft.template = options[i].$1),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: SdSpace.md),
            Text(l10n.templateEditLater, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      default:
        final logo = _draft.logoSourcePath == null ? null : File(_draft.logoSourcePath!);
        final shortName = _shortName.text.trim().isEmpty ? _name.text.trim() : _shortName.text.trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.brandColour, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: SdSpace.md),
            SdColorChoice(selected: _draft.brandColor, onChanged: (c) => setState(() => _draft.brandColor = c)),
            const SizedBox(height: SdSpace.xl),
            Wrap(
              spacing: SdSpace.sm,
              runSpacing: SdSpace.sm,
              children: [
                SdButton(
                  label: l10n.logoPick,
                  icon: Icons.image_outlined,
                  variant: SdButtonVariant.secondary,
                  onPressed: _pickLogo,
                ),
                if (logo != null)
                  SdButton(
                    label: l10n.logoRemove,
                    variant: SdButtonVariant.text,
                    onPressed: () => setState(() => _draft.logoSourcePath = null),
                  ),
              ],
            ),
            if (logo == null) ...[
              const SizedBox(height: SdSpace.sm),
              Text(l10n.logoNone, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: SdSpace.xl),
            Text(l10n.previewLabel, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: SdSpace.md),
            SdCard(
              child: Row(
                children: [
                  InstitutionSeal(
                    initials: _initials(shortName),
                    color: _draft.brandColor,
                    logoFile: logo,
                    size: 48,
                  ),
                  const SizedBox(width: SdSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(shortName, style: Theme.of(context).textTheme.titleMedium),
                        Text(l10n.academicYear(_yearLabel.text), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }

  static String _initials(String name) {
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return (words.first.length >= 2 ? words.first.substring(0, 2) : words.first).toUpperCase();
    return (words[0][0] + words[1][0]).toUpperCase();
  }
}
