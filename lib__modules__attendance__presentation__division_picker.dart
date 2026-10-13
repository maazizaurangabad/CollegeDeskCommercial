import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';

/// Class + division chooser for the active year. Choosing a class with a
/// single division selects that division straight away.
class DivisionPicker extends ConsumerStatefulWidget {
  const DivisionPicker({super.key, required this.divisionId, required this.onChanged});

  final String? divisionId;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<DivisionPicker> createState() => _DivisionPickerState();
}

class _DivisionPickerState extends ConsumerState<DivisionPicker> {
  String? _programId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final academic = ref.watch(academicControllerProvider);
    final programId = academic.divisions.where((d) => d.id == widget.divisionId).firstOrNull?.programId ?? _programId;
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final classField = SdSelectField<String>(
      label: l10n.fieldClass,
      value: programId,
      options: [
        for (final p in academic.programs)
          if (academic.divisionsOf(p.id).isNotEmpty) (p.id, p.name),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _programId = v);
        final divisions = academic.divisionsOf(v);
        widget.onChanged(divisions.length == 1 ? divisions.single.id : null);
      },
    );
    final divisionField = SdSelectField<String>(
      label: l10n.fieldDivision,
      value: widget.divisionId,
      options: programId == null ? const [] : [for (final d in academic.divisionsOf(programId)) (d.id, d.name)],
      onChanged: widget.onChanged,
    );
    if (!wide) return Column(children: [classField, divisionField]);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: classField),
        const SizedBox(width: SdSpace.md),
        Expanded(child: divisionField),
      ],
    );
  }
}
