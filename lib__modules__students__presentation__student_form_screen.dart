import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/ids/uuid7.dart';
import '../../../core/validation/aadhaar.dart';
import '../../../core/validation/mobile.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/organization/organization_providers.dart';
import '../application/students_providers.dart';
import '../domain/student_models.dart';
import 'student_labels.dart';

/// Add a new student ([studentId] null) or edit an existing one.
class StudentFormScreen extends ConsumerStatefulWidget {
  const StudentFormScreen({super.key, this.studentId});

  final String? studentId;

  @override
  ConsumerState<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends ConsumerState<StudentFormScreen> {
  final _form = GlobalKey<FormState>();
  StudentDraft? _draft;
  bool _hasSavedAadhaar = false;
  bool _removeAadhaar = false;
  String _aadhaarInput = '';
  String? _programId;
  String? _newPhotoPath;
  bool _saving = false;

  bool get _isEdit => widget.studentId != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!_isEdit) {
      setState(() => _draft = StudentDraft(guardians: [GuardianDraft(relation: 'Father', isPrimary: true)]));
      return;
    }
    final detail = await ref.read(studentRepositoryProvider).load(widget.studentId!);
    if (!mounted) return;
    if (detail == null) {
      context.go('/students');
      return;
    }
    final academic = ref.read(academicControllerProvider);
    setState(() {
      _draft = detail.draft;
      _hasSavedAadhaar = detail.identifier(IdentifierType.aadhaar) != null;
      _programId = academic.divisions.where((d) => d.id == detail.draft.divisionId).firstOrNull?.programId;
    });
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path != null) setState(() => _newPhotoPath = path);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final draft = _draft!;
    if (!(_form.currentState?.validate() ?? false)) {
      SdToast.show(context, l10n.issueRequiredExtra);
      return;
    }
    // Aadhaar is only sent when typed or removed, so the saved one is kept otherwise.
    draft.identifiers.remove(IdentifierType.aadhaar);
    if (_aadhaarInput.trim().isNotEmpty) {
      draft.identifiers[IdentifierType.aadhaar] = _aadhaarInput.trim();
    } else if (_removeAadhaar) {
      draft.identifiers[IdentifierType.aadhaar] = '';
    }
    for (final type in IdentifierType.values.where((t) => t != IdentifierType.aadhaar)) {
      draft.identifiers.putIfAbsent(type, () => '');
    }

    final repository = ref.read(studentRepositoryProvider);
    final duplicates = await repository.findDuplicates(draft, excludeId: widget.studentId);
    if (!mounted) return;
    if (duplicates.isNotEmpty) {
      final proceed = await _confirmDuplicates(duplicates);
      if (proceed != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      final mediaDir = ref.read(startupStateProvider).mediaDir;
      if (_newPhotoPath != null && mediaDir != null) {
        final dir = Directory(p.join(mediaDir.path, 'students'));
        await dir.create(recursive: true);
        final name = 'students/${Uuid7.generate()}${p.extension(_newPhotoPath!).toLowerCase()}';
        await File(_newPhotoPath!).copy(p.join(mediaDir.path, name));
        draft.photoFileName = name;
      }
      final extraFields = await ref.read(extraFieldsProvider.future);
      final String id;
      if (_isEdit) {
        await repository.update(widget.studentId!, draft, extraFields: extraFields);
        id = widget.studentId!;
      } else {
        id = await repository.create(draft, extraFields: extraFields);
      }
      ref.read(studentsRevisionProvider.notifier).state++;
      if (!mounted) return;
      SdToast.show(context, l10n.studentSaved);
      context.go('/students/$id');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        SdToast.show(context, studentErrorMessage(l10n, e));
      }
    }
  }

  Future<bool?> _confirmDuplicates(List<DuplicateMatch> matches) {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.duplicateTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in matches)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${m.fullName} (${m.displayCode})'),
                subtitle: Text(duplicateReasonLabel(l10n, m.reason)),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.of(dialog).pop(false);
                    context.go('/students/${m.studentId}');
                  },
                  child: Text(l10n.duplicateOpen),
                ),
              ),
          ],
        ),
        actions: [
          SdButton(label: l10n.cancel, variant: SdButtonVariant.text, onPressed: () => Navigator.of(dialog).pop(false)),
          SdButton(label: l10n.duplicateSaveAnyway, onPressed: () => Navigator.of(dialog).pop(true)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final draft = _draft;
    if (draft == null) {
      return const SdPage(children: [SdSkeleton(height: 48), SizedBox(height: SdSpace.lg), SdSkeleton(height: 320)]);
    }
    final academic = ref.watch(academicControllerProvider);
    final categories = ref.watch(studentCategoriesProvider).valueOrNull ?? StudentChoices.defaultCategories;
    final extraFields = ref.watch(extraFieldsProvider).valueOrNull ?? const <ExtraFieldDefinition>[];
    final canSeeSensitive = ref.watch(permissionCheckerProvider)('students.view_sensitive');
    final mediaDir = ref.watch(startupStateProvider).mediaDir;
    final photo = _newPhotoPath != null ? File(_newPhotoPath!) : studentPhoto(mediaDir, draft.photoFileName);
    List<(String, String)> choices(List<String> values) => [for (final v in values) (v, v)];

    String? number(String? v) => (v == null || v.trim().isEmpty || double.tryParse(v.trim()) != null) ? null : l10n.issueInvalidNumber;
    String? mobile(String? v) => (v == null || v.trim().isEmpty || MobileNumber.isValid(v)) ? null : l10n.fieldMobile;
    final digitsOnly = [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))];

    return SdPage(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.cancel,
              icon: const Icon(Icons.close),
              onPressed: () => context.go(_isEdit ? '/students/${widget.studentId}' : '/students'),
            ),
            const SizedBox(width: SdSpace.xs),
            Expanded(
              child: Text(_isEdit ? l10n.studentEditTitle : l10n.studentAddTitle, style: theme.textTheme.headlineSmall),
            ),
            SdButton(label: l10n.save, icon: Icons.check, onPressed: _saving ? null : _save),
          ],
        ),
        const SizedBox(height: SdSpace.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FormSection(title: l10n.sectionName, children: [
                Row(children: [
                  StudentAvatar(name: draft.fullName, photo: photo, size: 64),
                  const SizedBox(width: SdSpace.lg),
                  if (mediaDir != null)
                    SdButton(
                      label: l10n.photoPick,
                      icon: Icons.photo_camera_outlined,
                      variant: SdButtonVariant.secondary,
                      onPressed: _pickPhoto,
                    ),
                  if (photo != null)
                    SdButton(
                      label: l10n.photoRemove,
                      variant: SdButtonVariant.text,
                      onPressed: () => setState(() {
                        _newPhotoPath = null;
                        draft.photoFileName = null;
                      }),
                    ),
                ]),
                const SizedBox(height: SdSpace.lg),
                _text(l10n.fieldFirstName, draft.firstName, (v) => setState(() => draft.firstName = v),
                    validator: (v) => (v == null || v.trim().isEmpty) ? l10n.issueNameRequired : null),
                _text(l10n.fieldMiddleName, draft.middleName, (v) => draft.middleName = v),
                _text(l10n.fieldLastName, draft.lastName, (v) => draft.lastName = v),
                _text(l10n.fieldAltName, draft.altName, (v) => draft.altName = v, hint: l10n.fieldAltNameHint),
              ]),
              _FormSection(title: l10n.sectionPlacement, children: [
                if (academic.activeYear == null)
                  Text(l10n.placementNeedsYear, style: theme.textTheme.bodySmall)
                else ...[
                  SdSelectField<String>(
                    label: l10n.studentsFilterClass,
                    value: _programId,
                    options: [for (final p in academic.programs) (p.id, p.name)],
                    clearLabel: l10n.placementNone,
                    onChanged: (v) => setState(() {
                      _programId = v;
                      draft.divisionId = null;
                    }),
                  ),
                  if (_programId != null)
                    SdSelectField<String>(
                      label: l10n.studentsFilterDivision,
                      value: draft.divisionId,
                      options: [for (final d in academic.divisionsOf(_programId!)) (d.id, d.name)],
                      onChanged: (v) => setState(() => draft.divisionId = v),
                    ),
                  _text(
                    l10n.fieldRollNumber,
                    draft.rollNumber?.toString() ?? '',
                    (v) => draft.rollNumber = int.tryParse(v.trim()),
                    keyboard: TextInputType.number,
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ],
              ]),
              _FormSection(title: l10n.sectionPersonal, children: [
                SdSelectField<String>(
                  label: l10n.fieldGender,
                  value: draft.gender,
                  options: choices(StudentChoices.genders),
                  clearLabel: l10n.notSet,
                  onChanged: (v) => setState(() => draft.gender = v),
                ),
                SdDateField(
                  label: l10n.fieldDateOfBirth,
                  value: draft.dateOfBirth,
                  onChanged: (v) => setState(() => draft.dateOfBirth = v),
                ),
                _text(l10n.fieldPlaceOfBirth, draft.placeOfBirth, (v) => draft.placeOfBirth = v),
                _text(l10n.fieldNationality, draft.nationality, (v) => draft.nationality = v),
                _text(l10n.fieldMotherTongue, draft.motherTongue, (v) => draft.motherTongue = v),
                SdSelectField<String>(
                  label: l10n.fieldCategory,
                  value: draft.category,
                  options: choices({...categories, if (draft.category != null) draft.category!}.toList()),
                  clearLabel: l10n.notSet,
                  onChanged: (v) => setState(() => draft.category = v),
                ),
                if (canSeeSensitive) ...[
                  _text(l10n.fieldCaste, draft.caste, (v) => draft.caste = v, hint: l10n.sensitiveNote),
                  _text(l10n.fieldSubCaste, draft.subCaste, (v) => draft.subCaste = v),
                ],
                _text(l10n.fieldAddress, draft.address, (v) => draft.address = v, maxLines: 2),
              ]),
              _FormSection(title: l10n.sectionHealth, children: [
                SdSelectField<String>(
                  label: l10n.fieldBloodGroup,
                  value: draft.bloodGroup,
                  options: choices(StudentChoices.bloodGroups),
                  clearLabel: l10n.notSet,
                  onChanged: (v) => setState(() => draft.bloodGroup = v),
                ),
                _text(l10n.fieldHeight, draft.heightCm?.toString() ?? '', (v) => draft.heightCm = double.tryParse(v.trim()),
                    keyboard: const TextInputType.numberWithOptions(decimal: true), validator: number),
                _text(l10n.fieldWeight, draft.weightKg?.toString() ?? '', (v) => draft.weightKg = double.tryParse(v.trim()),
                    keyboard: const TextInputType.numberWithOptions(decimal: true), validator: number),
                SdDateField(
                  label: l10n.fieldMeasuredOn,
                  value: draft.measuredOn,
                  onChanged: (v) => setState(() => draft.measuredOn = v),
                ),
              ]),
              _FormSection(title: l10n.sectionGuardians, children: [
                for (var i = 0; i < draft.guardians.length; i++)
                  _GuardianEditor(
                    key: ObjectKey(draft.guardians[i]),
                    number: i + 1,
                    guardian: draft.guardians[i],
                    mobileValidator: mobile,
                    onPrimary: () => setState(() {
                      for (final g in draft.guardians) {
                        g.isPrimary = identical(g, draft.guardians[i]);
                      }
                    }),
                    onRemove: () => setState(() => draft.guardians.removeAt(i)),
                    onRelation: (v) => setState(() => draft.guardians[i].relation = v),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SdButton(
                    label: l10n.guardianAdd,
                    icon: Icons.add,
                    variant: SdButtonVariant.secondary,
                    onPressed: () => setState(
                      () => draft.guardians.add(GuardianDraft(relation: 'Mother', isPrimary: draft.guardians.isEmpty)),
                    ),
                  ),
                ),
              ]),
              _FormSection(title: l10n.sectionIdentifiers, children: [
                for (final type in IdentifierType.values.where((t) => t != IdentifierType.aadhaar))
                  _text(identifierLabel(l10n, type), draft.identifiers[type] ?? '', (v) => draft.identifiers[type] = v,
                      keyboard: TextInputType.text),
                _text(
                  l10n.idAadhaar,
                  '',
                  (v) => _aadhaarInput = v,
                  keyboard: TextInputType.number,
                  formatters: digitsOnly,
                  hint: _hasSavedAadhaar && !_removeAadhaar ? l10n.aadhaarKeep : l10n.aadhaarHint,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty || Aadhaar.isValid(v)) ? null : l10n.issueInvalidAadhaar,
                ),
                if (_hasSavedAadhaar && !_removeAadhaar)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SdButton(
                      label: l10n.aadhaarRemove,
                      variant: SdButtonVariant.text,
                      onPressed: () => setState(() => _removeAadhaar = true),
                    ),
                  ),
              ]),
              _FormSection(title: l10n.sectionAdmission, children: [
                SdDateField(
                  label: l10n.fieldAdmissionDate,
                  value: draft.admissionDate,
                  onChanged: (v) => setState(() => draft.admissionDate = v),
                ),
                _text(l10n.fieldPreviousSchool, draft.previousSchool, (v) => draft.previousSchool = v),
              ]),
              if (extraFields.isNotEmpty)
                _FormSection(title: l10n.sectionExtra, children: [
                  for (final f in extraFields) _extraField(l10n, draft, f),
                ]),
              _FormSection(title: l10n.sectionNotes, children: [
                _text(l10n.fieldNotes, draft.notes, (v) => draft.notes = v, maxLines: 3, keyboard: TextInputType.multiline),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: SdButton(label: l10n.save, icon: Icons.check, onPressed: _saving ? null : _save),
              ),
              const SizedBox(height: SdSpace.xxl),
            ],
          ),
        ),
      ],
    );
  }

  Widget _text(
    String label,
    String initial,
    ValueChanged<String> onChanged, {
    FormFieldValidator<String>? validator,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? hint,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.lg),
      child: TextFormField(
        initialValue: initial,
        onChanged: onChanged,
        validator: validator,
        keyboardType: keyboard,
        inputFormatters: formatters,
        maxLines: maxLines,
        textCapitalization: keyboard == null ? TextCapitalization.words : TextCapitalization.none,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Widget _extraField(
    AppLocalizations l10n,
    StudentDraft draft,
    ExtraFieldDefinition f,
  ) {
    final label = f.isRequired ? '${f.label} *' : f.label;
    String? required(String? v) => f.isRequired && (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null;
    switch (f.type) {
      case 'number':
        return _text(label, draft.extra[f.key] ?? '', (v) => draft.extra[f.key] = v,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => required(v) ?? ((v == null || v.isEmpty || double.tryParse(v) != null) ? null : l10n.issueInvalidNumber));
      case 'date':
        return SdDateField(
          label: label,
          value: DateTime.tryParse(draft.extra[f.key] ?? ''),
          onChanged: (v) => setState(() => draft.extra[f.key] = v == null ? '' : v.toIso8601String().substring(0, 10)),
        );
      case 'choice':
        return SdSelectField<String>(
          label: label,
          value: draft.extra[f.key],
          options: [for (final o in f.options) (o, o)],
          clearLabel: l10n.notSet,
          onChanged: (v) => setState(() => draft.extra[f.key] = v ?? ''),
        );
      case 'yesNo':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: draft.extra[f.key] == 'true',
          onChanged: (v) => setState(() => draft.extra[f.key] = '$v'),
        );
      default:
        return _text(label, draft.extra[f.key] ?? '', (v) => draft.extra[f.key] = v, validator: required);
    }
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.xl),
      child: SdSection(
        title: title,
        child: SdCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
      ),
    );
  }
}

class _GuardianEditor extends StatelessWidget {
  const _GuardianEditor({
    super.key,
    required this.number,
    required this.guardian,
    required this.mobileValidator,
    required this.onPrimary,
    required this.onRemove,
    required this.onRelation,
  });

  final ValueChanged<String> onRelation;
  final int number;
  final GuardianDraft guardian;
  final FormFieldValidator<String> mobileValidator;
  final VoidCallback onPrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget field(String label, String initial, ValueChanged<String> onChanged,
        {TextInputType? keyboard, FormFieldValidator<String>? validator}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: SdSpace.md),
        child: TextFormField(
          initialValue: initial,
          onChanged: onChanged,
          keyboardType: keyboard,
          validator: validator,
          textCapitalization: keyboard == null ? TextCapitalization.words : TextCapitalization.none,
          decoration: InputDecoration(labelText: label),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.guardianNumber(number), style: Theme.of(context).textTheme.titleSmall)),
              TextButton(onPressed: onRemove, child: Text(l10n.guardianRemove)),
            ],
          ),
          field(l10n.fieldName, guardian.name, (v) => guardian.name = v),
          SdSelectField<String>(
            label: l10n.fieldRelation,
            value: guardian.relation,
            options: [for (final r in StudentChoices.relations) (r, r)],
            onChanged: (v) {
              if (v != null) onRelation(v);
            },
          ),
          field(l10n.fieldMobile, guardian.mobile, (v) => guardian.mobile = v,
              keyboard: TextInputType.phone, validator: mobileValidator),
          field(l10n.fieldAltMobile, guardian.altMobile, (v) => guardian.altMobile = v,
              keyboard: TextInputType.phone, validator: mobileValidator),
          field(l10n.fieldEmail, guardian.email, (v) => guardian.email = v, keyboard: TextInputType.emailAddress),
          field(l10n.fieldOccupation, guardian.occupation, (v) => guardian.occupation = v),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l10n.fieldPrimaryContact),
            value: guardian.isPrimary,
            onChanged: (_) => onPrimary(),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
