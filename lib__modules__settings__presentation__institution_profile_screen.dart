import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/startup/app_bootstrap.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/organization/institution_seal.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../../platform/workspace/presentation/institution_form_fields.dart';
import '../../../platform/workspace/workspace_actions.dart';
import 'settings_page_header.dart';

class InstitutionProfileScreen extends ConsumerStatefulWidget {
  const InstitutionProfileScreen({super.key});

  @override
  ConsumerState<InstitutionProfileScreen> createState() => _InstitutionProfileScreenState();
}

class _InstitutionProfileScreenState extends ConsumerState<InstitutionProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late String _type;
  late Color _brand;
  String? _logoFileName;
  String? _newLogoPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final org = ref.read(activeOrganizationProvider);
    TextEditingController t(String? v) => TextEditingController(text: v ?? '');
    _c = {
      'name': t(org.name),
      'shortName': t(org.shortName),
      'address': t(org.address),
      'city': t(org.city),
      'state': t(org.state),
      'phone': t(org.phone),
      'email': t(org.email),
      'website': t(org.website),
      'udise': t(org.udiseCode),
      'board': t(org.board),
      'medium': t(org.medium),
      'programLabel': t(org.programLabel),
      'divisionLabel': t(org.divisionLabel),
    };
    _type = org.institutionType;
    _brand = org.brandColor;
    _logoFileName = org.logoFileName;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path != null) setState(() => _newLogoPath = path);
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final ok = await runWithFeedback(context, () async {
      final org = ref.read(activeOrganizationProvider);
      final mediaDir = ref.read(startupStateProvider).mediaDir;
      var logo = _logoFileName ?? '';
      if (_newLogoPath != null && mediaDir != null) logo = await AppBootstrap.storeLogo(mediaDir, _newLogoPath!);
      final edited = org.copyWith(
        name: _c['name']!.text,
        shortName: _c['shortName']!.text,
        institutionType: _type,
        city: _c['city']!.text,
        brandColor: _brand,
        address: _c['address']!.text,
        state: _c['state']!.text,
        phone: _c['phone']!.text,
        email: _c['email']!.text,
        website: _c['website']!.text,
        udiseCode: _c['udise']!.text,
        board: _c['board']!.text,
        medium: _c['medium']!.text,
        logoFileName: logo,
        programLabel: _c['programLabel']!.text,
        divisionLabel: _c['divisionLabel']!.text,
      );
      final repository = ref.read(organizationRepositoryProvider);
      await repository.update(edited);
      final saved = await repository.loadActive();
      if (saved != null) ref.read(activeOrganizationProvider.notifier).state = saved;
      await ref.read(workspaceActionsProvider).renameCurrent(edited.name.trim());
      _logoFileName = saved?.logoFileName;
      _newLogoPath = null;
    }, (_) => l10n.saveFailed);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) SdToast.show(context, l10n.saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final org = ref.watch(activeOrganizationProvider);
    final mediaDir = ref.watch(startupStateProvider).mediaDir;
    final logo = _newLogoPath != null ? File(_newLogoPath!) : InstitutionSeal.logoIn(mediaDir, _logoFileName);

    return SdPage(
      children: [
        SettingsPageHeader(
          title: l10n.settingsInstitutionProfile,
          trailing: SdButton(label: l10n.save, onPressed: _saving ? null : _save),
        ),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormFieldRow(controller: _c['name']!, label: l10n.fieldName, validator: (v) => requiredText(l10n, v)),
              FormFieldRow(
                controller: _c['shortName']!,
                label: l10n.fieldShortName,
                hint: l10n.fieldShortNameHint,
                validator: (v) => requiredText(l10n, v),
              ),
              InstitutionTypeChoice(value: _type, onChanged: (t) => setState(() => _type = t)),
              FormFieldRow(controller: _c['address']!, label: l10n.fieldAddress, maxLines: 2),
              FormFieldRow(controller: _c['city']!, label: l10n.fieldCity),
              FormFieldRow(controller: _c['state']!, label: l10n.fieldState),
              FormFieldRow(controller: _c['phone']!, label: l10n.fieldPhone, keyboardType: TextInputType.phone),
              FormFieldRow(
                controller: _c['email']!,
                label: l10n.fieldEmail,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => optionalEmail(l10n, v),
              ),
              FormFieldRow(controller: _c['website']!, label: l10n.fieldWebsite, keyboardType: TextInputType.url),
              FormFieldRow(controller: _c['udise']!, label: l10n.fieldUdise, keyboardType: TextInputType.number),
              FormFieldRow(controller: _c['board']!, label: l10n.fieldBoard, hint: l10n.fieldBoardHint),
              FormFieldRow(controller: _c['medium']!, label: l10n.fieldMedium, hint: l10n.fieldMediumHint),
              const SizedBox(height: SdSpace.md),
              Text(l10n.labelsTitle, style: theme.textTheme.titleSmall),
              const SizedBox(height: SdSpace.md),
              FormFieldRow(
                controller: _c['programLabel']!,
                label: l10n.fieldProgramLabel,
                hint: l10n.defaultProgramLabel,
              ),
              FormFieldRow(
                controller: _c['divisionLabel']!,
                label: l10n.fieldDivisionLabel,
                hint: l10n.defaultDivisionLabel,
              ),
            ],
          ),
        ),
        const SizedBox(height: SdSpace.md),
        Text(l10n.setupBrandingTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: SdSpace.md),
        Row(
          children: [
            InstitutionSeal(initials: org.initials, color: _brand, logoFile: logo, size: 56),
            const SizedBox(width: SdSpace.lg),
            if (mediaDir != null)
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
                onPressed: () => setState(() {
                  _newLogoPath = null;
                  _logoFileName = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: SdSpace.lg),
        SdColorChoice(selected: _brand, onChanged: (c) => setState(() => _brand = c)),
        const SizedBox(height: SdSpace.xxl),
      ],
    );
  }
}
