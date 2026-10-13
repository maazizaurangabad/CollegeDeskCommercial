import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/ids/uuid7.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/data_providers.dart';
import '../application/students_providers.dart';
import '../domain/student_models.dart';
import '../import/import_repository.dart';
import '../import/photo_matcher.dart';
import '../import/photo_resize.dart';

/// Matches many photo files to students by file name and saves them, resized.
class PhotoImportScreen extends ConsumerStatefulWidget {
  const PhotoImportScreen({super.key});

  @override
  ConsumerState<PhotoImportScreen> createState() => _PhotoImportScreenState();
}

class _PhotoImportScreenState extends ConsumerState<PhotoImportScreen> {
  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'};

  /// file name -> bytes
  final Map<String, Uint8List> _files = {};
  String _sourceName = '';
  List<StudentKeys> _students = const [];
  List<ImportBatchInfo> _studentImports = const [];
  String? _serialBatchId;
  Map<String, String> _serials = const {};
  String? _rollDivisionId;
  String? _rollProgramId;
  PhotoKey? _key;
  PhotoKey? _suggested;
  bool _replace = false;
  bool _busy = false;
  int _done = 0;
  (int, int)? _result;

  PhotoMatcher get _matcher => PhotoMatcher(_students, serials: _serials, divisionId: _rollDivisionId);

  Future<void> _choose() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'zip'],
    );
    if (picked == null) return;
    setState(() => _busy = true);
    final files = <String, Uint8List>{};
    for (final f in picked.files) {
      if (f.path == null) continue;
      final bytes = await File(f.path!).readAsBytes();
      if (p.extension(f.path!).toLowerCase() == '.zip') {
        for (final entry in ZipDecoder().decodeBytes(bytes)) {
          final name = p.basename(entry.name);
          if (!entry.isFile || name.startsWith('.') || !_imageExtensions.contains(p.extension(name).toLowerCase())) {
            continue;
          }
          files[name] = Uint8List.fromList(entry.content as List<int>);
        }
      } else {
        files[p.basename(f.path!)] = bytes;
      }
    }
    final yearId = ref.read(academicControllerProvider).activeYear?.id;
    _students = await ref.read(studentRepositoryProvider).matchingKeys(yearId);
    _studentImports =
        (await ref.read(importRepositoryProvider).listBatches()).where((b) => b.kind == 'students' && !b.undone).toList();
    if (_studentImports.isNotEmpty && _serialBatchId == null) await _useSerialBatch(_studentImports.first.id);
    setState(() {
      _files
        ..clear()
        ..addAll(files);
      _sourceName = picked.files.length == 1 ? picked.files.single.name : '${picked.files.length} files';
      _busy = false;
      _suggest();
    });
  }

  Future<void> _useSerialBatch(String batchId) async {
    _serialBatchId = batchId;
    _serials = await ref.read(importRepositoryProvider).serialMap(batchId);
  }

  void _suggest() {
    if (_files.isEmpty) return;
    final (key, count) = _matcher.bestKey(_files.keys.toList());
    _suggested = count > 0 ? key : null;
    _key ??= _suggested ?? PhotoKey.grNumber;
  }

  Future<void> _save(List<PhotoMatch> matches) async {
    final l10n = AppLocalizations.of(context);
    final mediaDir = ref.read(startupStateProvider).mediaDir;
    if (mediaDir == null) return;
    final toSave = matches.where((m) => m.student != null && (_replace || !m.student!.hasPhoto)).toList();
    setState(() {
      _busy = true;
      _done = 0;
    });
    final imports = ref.read(importRepositoryProvider);
    final students = ref.read(studentRepositoryProvider);
    final batchId = await imports.startPhotoBatch(_sourceName, _key!.name);
    final dir = Directory(p.join(mediaDir.path, 'students'));
    await dir.create(recursive: true);
    var saved = 0;
    var skipped = matches.length - toSave.length;
    for (var i = 0; i < toSave.length; i++) {
      final m = toSave[i];
      final resized = await resizeStudentPhoto(_files[m.fileName]!);
      if (resized == null) {
        skipped++;
      } else {
        final name = 'students/${Uuid7.generate()}.jpg';
        await File(p.join(mediaDir.path, name)).writeAsBytes(resized, flush: true);
        final previous = await students.setPhoto(m.student!.id, name);
        await imports.recordPhoto(batchId, i + 1, m.student!.id, previous);
        saved++;
      }
      if (mounted) setState(() => _done = i + 1);
    }
    await imports.finishPhotoBatch(batchId, added: saved, skipped: skipped);
    ref.read(studentsRevisionProvider.notifier).state++;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = (saved, skipped);
    });
    SdToast.show(context, l10n.photosDone);
  }

  String _keyLabel(AppLocalizations l10n, PhotoKey key) => switch (key) {
        PhotoKey.serialNo => l10n.keySerial,
        PhotoKey.grNumber => l10n.keyGr,
        PhotoKey.admissionNumber => l10n.keyAdmission,
        PhotoKey.studentCode => l10n.keyCode,
        PhotoKey.pen => l10n.keyPen,
        PhotoKey.apaar => l10n.keyApaar,
        PhotoKey.saralId => l10n.keySaral,
        PhotoKey.rollInDivision => l10n.keyRoll,
        PhotoKey.fullName => l10n.keyName,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final academic = ref.watch(academicControllerProvider);
    final matches = _files.isEmpty || _key == null ? <PhotoMatch>[] : _matcher.match(_files.keys.toList()..sort(), _key!);
    final matched = matches.where((m) => m.student != null).toList();
    final unmatched = matches.where((m) => m.student == null).toList();
    final withPhoto = matched.where((m) => m.student!.hasPhoto).length;

    return SdPage(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.back,
              icon: const Icon(Icons.arrow_back),
              onPressed: _busy ? null : () => context.go('/students'),
            ),
            const SizedBox(width: SdSpace.xs),
            Expanded(child: Text(l10n.importPhotosTitle, style: theme.textTheme.headlineSmall)),
          ],
        ),
        const SizedBox(height: SdSpace.lg),
        Text(l10n.photosIntro),
        const SizedBox(height: SdSpace.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: SdButton(
            label: l10n.photosChoose,
            icon: Icons.photo_library_outlined,
            variant: _files.isEmpty ? SdButtonVariant.primary : SdButtonVariant.secondary,
            onPressed: _busy ? null : _choose,
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: SdSpace.lg),
          LinearProgressIndicator(value: _result == null && _done > 0 && matched.isNotEmpty ? _done / matched.length : null),
          if (_done > 0) Text(l10n.photosProgress(_done, matched.length), style: theme.textTheme.bodySmall),
        ],
        if (_result != null) ...[
          const SizedBox(height: SdSpace.xl),
          SdEmptyState(
            icon: Icons.task_alt,
            title: l10n.photosDone,
            message: l10n.photosSummary(_result!.$1, _result!.$2),
            action: SdButton(label: l10n.importOpenStudents, onPressed: () => context.go('/students')),
          ),
        ] else if (_files.isNotEmpty) ...[
          const SizedBox(height: SdSpace.xl),
          SdSection(
            title: l10n.photosFound(_files.length),
            child: SdCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SdSelectField<PhotoKey>(
                    label: l10n.photosMatchBy,
                    value: _key,
                    options: [
                      for (final k in PhotoKey.values)
                        (k, k == _suggested ? '${_keyLabel(l10n, k)} — ${l10n.photosBestGuess}' : _keyLabel(l10n, k)),
                    ],
                    onChanged: (v) => setState(() => _key = v),
                  ),
                  if (_key == PhotoKey.serialNo && _studentImports.isNotEmpty)
                    SdSelectField<String>(
                      label: l10n.photosImportBatch,
                      value: _serialBatchId,
                      options: [for (final b in _studentImports) (b.id, b.sourceName)],
                      onChanged: (v) async {
                        if (v == null) return;
                        await _useSerialBatch(v);
                        setState(() {});
                      },
                    ),
                  if (_key == PhotoKey.rollInDivision) ...[
                    SdSelectField<String>(
                      label: l10n.fieldClass,
                      value: _rollProgramId,
                      options: [for (final p in academic.programs) (p.id, p.name)],
                      onChanged: (v) => setState(() {
                        _rollProgramId = v;
                        _rollDivisionId = null;
                      }),
                    ),
                    if (_rollProgramId != null)
                      SdSelectField<String>(
                        label: l10n.photosDivisionForRoll,
                        value: _rollDivisionId,
                        options: [for (final d in academic.divisionsOf(_rollProgramId!)) (d.id, d.name)],
                        onChanged: (v) => setState(() => _rollDivisionId = v),
                      ),
                  ],
                  if (withPhoto > 0)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.photosReplace),
                      subtitle: Text('${l10n.photosHasPhoto}: $withPhoto'),
                      value: _replace,
                      onChanged: (v) => setState(() => _replace = v),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SdSpace.lg),
          Wrap(
            spacing: SdSpace.md,
            runSpacing: SdSpace.sm,
            children: [
              Chip(avatar: Icon(Icons.check_circle, color: sd.present, size: 18), label: Text('${l10n.photosMatched}: ${matched.length}')),
              Chip(avatar: Icon(Icons.help_outline, color: sd.absent, size: 18), label: Text('${l10n.photosUnmatched}: ${unmatched.length}')),
            ],
          ),
          const SizedBox(height: SdSpace.lg),
          SdCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final m in [...unmatched, ...matched].take(200))
                  ListTile(
                    dense: true,
                    leading: Icon(
                      m.student == null ? Icons.help_outline : Icons.check_circle_outline,
                      color: m.student == null ? sd.absent : sd.present,
                    ),
                    title: Text(m.fileName),
                    subtitle: Text(
                      m.student != null
                          ? '${m.student!.fullName} (${m.student!.displayCode})${m.student!.hasPhoto ? ' · ${l10n.photosHasPhoto}' : ''}'
                          : (m.ambiguous ? l10n.photosAmbiguous : l10n.photosUnmatched),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: SdSpace.lg),
          Align(
            alignment: Alignment.centerRight,
            child: SdButton(
              label: l10n.photosSave,
              icon: Icons.check,
              onPressed: _busy || matched.isEmpty ? null : () => _save(matches),
            ),
          ),
          const SizedBox(height: SdSpace.xxl),
        ],
      ],
    );
  }
}
