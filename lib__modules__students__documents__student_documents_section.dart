import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/files/save_file.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../../platform/reporting/report_output.dart';
import '../domain/student_models.dart';
import '../presentation/student_labels.dart';
import '../presentation/student_profile_cards.dart';
import 'document_files.dart';
import 'document_models.dart';
import 'document_providers.dart';
import 'documents_pdf.dart';

enum _Source { scan, camera, upload }

final _date = DateFormat('d MMM y');

/// The Documents tab of a student's profile: every document type with
/// its status, details and scanned pages. Pages come from the document
/// scanner or camera (Android) or from files (any device).
class StudentDocumentsSection extends ConsumerStatefulWidget {
  const StudentDocumentsSection({super.key, required this.detail, this.programId, this.classLine});

  final StudentDetail detail;

  /// The student's class this year (for "required for these classes").
  final String? programId;
  final String? classLine;

  @override
  ConsumerState<StudentDocumentsSection> createState() => _StudentDocumentsSectionState();
}

class _StudentDocumentsSectionState extends ConsumerState<StudentDocumentsSection> {
  bool _busy = false;

  bool _can(String permission) => ref.read(permissionCheckerProvider)(permission);
  bool _mayOpen(DocumentType t) => !t.sensitive || _can('students.view_sensitive');

  void _changed() => ref.read(documentsRevisionProvider.notifier).state++;

  // ================================================================= pages

  /// Pages picked, scanned or photographed, saved into the media folder.
  Future<List<String>> _pickPages(_Source source) async {
    final l10n = AppLocalizations.of(context);
    final files = ref.read(documentFilesProvider);
    if (files == null) return const [];
    final studentId = widget.detail.id;
    final saved = <String>[];
    try {
      switch (source) {
        case _Source.scan:
          final scanner = DocumentScanner(
            // Pages come back as JPEG pictures (the scanner's standard).
            options: DocumentScannerOptions(
              mode: ScannerMode.full,
              pageLimit: 20,
              isGalleryImport: true,
            ),
          );
          Object? failure;
          try {
            final result = await scanner.scanDocument();
            final List<String>? pages = result.images;
            for (final path in pages ?? const <String>[]) {
              saved.add(await files.addImage(studentId, await File(path).readAsBytes()));
            }
            if (saved.isEmpty && mounted) SdToast.show(context, l10n.docScanNoPages);
          } on DocumentTooLarge {
            rethrow;
          } on DocumentUnreadable {
            rethrow;
          } catch (e) {
            // Closing the scanner without scanning is not an error.
            if (!_isScanCancel(e)) failure = e;
          } finally {
            await scanner.close();
          }
          if (failure != null && mounted) {
            final useCamera = await SdDialog.confirm(
              context,
              title: l10n.docScanFailedTitle,
              message: l10n.docScanFailedMessage(_scanReason(failure)),
              confirmLabel: l10n.docCamera,
              cancelLabel: l10n.cancel,
            );
            if (useCamera && mounted) return _pickPages(_Source.camera);
          }
        case _Source.camera:
          final shot = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2400, imageQuality: 90);
          if (shot != null) saved.add(await files.addImage(studentId, await shot.readAsBytes()));
        case _Source.upload:
          final picked = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
            allowMultiple: true,
          );
          for (final f in picked?.files ?? const <PlatformFile>[]) {
            final path = f.path;
            if (path == null) continue;
            final bytes = await File(path).readAsBytes();
            saved.add(path.toLowerCase().endsWith('.pdf')
                ? await files.addPdf(studentId, bytes)
                : await files.addImage(studentId, bytes));
          }
      }
    } on DocumentTooLarge {
      if (mounted) SdToast.show(context, l10n.docTooLarge);
    } on DocumentUnreadable {
      if (mounted) SdToast.show(context, l10n.docUnreadable);
    } catch (_) {
      // Camera or file picker closed without choosing anything.
    }
    return saved;
  }

  /// The scanner reports "Operation cancelled" when the user closes it.
  bool _isScanCancel(Object e) => e.toString().toLowerCase().contains('cancel');

  /// A short, readable reason from the scanner's error (for screenshots).
  String _scanReason(Object e) {
    var text = e.toString();
    if (e is PlatformException) text = e.message ?? e.code;
    text = text.replaceAll(RegExp(r'^[\w.]*Exception:\s*'), '').trim();
    if (text.length > 160) text = '${text.substring(0, 160)}…';
    return text.isEmpty ? '-' : text;
  }

  Future<void> _addPages(DocumentLine line, _Source source) async {
    setState(() => _busy = true);
    try {
      final added = await _pickPages(source);
      if (added.isEmpty) return;
      final base = line.document ?? StudentDocument(studentId: widget.detail.id, typeKey: line.type.key);
      await ref.read(documentRepositoryProvider).save(
            base.copyWith(status: DocumentStatus.received, files: [...base.files, ...added]),
          );
      _changed();
      if (mounted) SdToast.show(context, AppLocalizations.of(context).docPagesAdded(added.length));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // =================================================================== pdf

  Future<List<Uint8List>> _pagesOf(StudentDocument d) async {
    final files = ref.read(documentFilesProvider);
    if (files == null) return const [];
    final pages = <Uint8List>[];
    for (final f in d.files) {
      final bytes = await files.read(f);
      if (bytes == null) continue;
      if (DocumentFiles.isPdf(f)) {
        await for (final page in Printing.raster(bytes, dpi: 144)) {
          pages.add(await page.toPng());
        }
      } else {
        pages.add(bytes);
      }
    }
    return pages;
  }

  String _details(AppLocalizations l10n, StudentDocument d) => [
        if ((d.number ?? '').isNotEmpty) '${l10n.docNumber}: ${d.number}',
        if (d.issuedOn != null) '${l10n.docIssuedOn}: ${_date.format(d.issuedOn!)}',
        d.isOriginal ? l10n.docOriginal : l10n.docCopy,
        if (d.verified) l10n.docVerified,
      ].join(' · ');

  /// One document, or all of them, as a single PDF to view, save or share.
  Future<void> _openPdf(List<DocumentLine> lines) async {
    final l10n = AppLocalizations.of(context);
    final withFiles = [
      for (final l in lines)
        if (l.document != null && l.document!.hasFiles && _mayOpen(l.type)) l,
    ];
    if (withFiles.isEmpty) {
      SdToast.show(context, l10n.docNoFiles);
      return;
    }
    setState(() => _busy = true);
    try {
      final d = widget.detail;
      final name = d.draft.fullName;
      final single = withFiles.length == 1;
      Uint8List bytes;
      // A single uploaded PDF is given back exactly as it was.
      final only = withFiles.first.document!;
      if (single && only.files.length == 1 && DocumentFiles.isPdf(only.files.single)) {
        bytes = (await ref.read(documentFilesProvider)!.read(only.files.single)) ?? Uint8List(0);
      } else {
        bytes = await buildDocumentsPdf(
          title: single ? '${withFiles.first.type.label} – $name' : l10n.docAllTitle(name),
          about: [
            name,
            [d.displayCode, if (d.identifier(IdentifierType.grNumber) case final gr?) '${l10n.idGr} $gr', if (widget.classLine != null) widget.classLine!]
                .join(' · '),
          ],
          parts: [
            for (final l in withFiles)
              (label: l.type.label, details: _details(l10n, l.document!), pages: await _pagesOf(l.document!)),
          ],
          fonts: await ReportOutput.fonts(),
          generatedLine: l10n.docGenerated(_date.format(DateTime.now())),
        );
      }
      final file = '${single ? withFiles.first.type.key : 'documents'}-${d.displayCode}';
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _PdfPage(title: single ? withFiles.first.type.label : l10n.docAll, fileName: file, bytes: bytes),
      ));
    } catch (_) {
      if (mounted) SdToast.show(context, l10n.docPdfFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ================================================================= build

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sd = SdColors.of(context);
    final types = ref.watch(documentTypesProvider).valueOrNull ?? DocumentTypes.defaults;
    final docsAsync = ref.watch(studentDocumentsProvider(widget.detail.id));
    final canEdit = _can('students.edit');
    return ProfileCard(
      icon: Icons.folder_copy_outlined,
      title: l10n.docTitle,
      action: TextButton.icon(
        onPressed: _busy
            ? null
            : () => _openPdf(documentChecklist(types, docsAsync.valueOrNull ?? const [],
                programId: widget.programId, category: widget.detail.draft.category)),
        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
        label: Text(l10n.docDownloadAll),
      ),
      child: profileAsync<List<StudentDocument>>(context, docsAsync, (docs) {
        final lines = documentChecklist(types, docs, programId: widget.programId, category: widget.detail.draft.category);
        final missing = lines.where(isMissing).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const Padding(padding: EdgeInsets.only(bottom: SdSpace.sm), child: LinearProgressIndicator()),
            Text(
              missing == 0 ? l10n.docAllReceived : l10n.docMissingCount(missing),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: missing == 0 ? sd.present : sd.leave),
            ),
            const SizedBox(height: SdSpace.sm),
            for (final line in lines)
              _DocumentTile(
                line: line,
                canOpen: _mayOpen(line.type),
                canEdit: canEdit,
                busy: _busy,
                onTap: canEdit ? () => _edit(line) : null,
                onAdd: (s) => _addPages(line, s),
                onPdf: () => _openPdf([line]),
              ),
            const SizedBox(height: SdSpace.sm),
            Text(l10n.docHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: sd.textMuted)),
          ],
        );
      }),
    );
  }

  Future<void> _edit(DocumentLine line) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DocumentEditor(
        line: line,
        studentId: widget.detail.id,
        canOpen: _mayOpen(line.type),
      ),
    );
    if (saved == true) _changed();
  }
}

/// Which ways of adding pages this device has.
List<_Source> get _sources => [if (Platform.isAndroid) ...[_Source.scan, _Source.camera], _Source.upload];

String _sourceLabel(AppLocalizations l10n, _Source s) => switch (s) {
      _Source.scan => l10n.docScan,
      _Source.camera => l10n.docCamera,
      _Source.upload => l10n.docUpload,
    };

IconData _sourceIcon(_Source s) => switch (s) {
      _Source.scan => Icons.document_scanner_outlined,
      _Source.camera => Icons.photo_camera_outlined,
      _Source.upload => Icons.upload_file_outlined,
    };

String docStatusLabel(AppLocalizations l10n, DocumentStatus? s) => switch (s) {
      DocumentStatus.received => l10n.docReceived,
      DocumentStatus.pending => l10n.docPending,
      DocumentStatus.notNeeded => l10n.docNotNeeded,
      null => l10n.docNotRecorded,
    };

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.line,
    required this.canOpen,
    required this.canEdit,
    required this.busy,
    required this.onAdd,
    required this.onPdf,
    this.onTap,
  });

  final DocumentLine line;
  final bool canOpen;
  final bool canEdit;
  final bool busy;
  final ValueChanged<_Source> onAdd;
  final VoidCallback onPdf;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sd = SdColors.of(context);
    final d = line.document;
    final status = d?.status;
    final color = switch (status) {
      DocumentStatus.received => sd.present,
      DocumentStatus.notNeeded => sd.textMuted,
      _ => line.isRequired ? sd.leave : sd.textMuted,
    };
    final sub = [
      docStatusLabel(l10n, status),
      if (d != null && d.hasFiles) l10n.docPages(d.files.length),
      if (d != null && (d.number ?? '').isNotEmpty) d.number!,
      if (d != null && d.verified) l10n.docVerified,
      if (d != null && d.returnedOn != null) l10n.docReturnedOn(_date.format(d.returnedOn!)),
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        status == DocumentStatus.received ? Icons.check_circle : (line.isRequired ? Icons.error_outline : Icons.circle_outlined),
        color: color,
      ),
      title: Row(children: [
        Flexible(child: Text(line.type.label)),
        if (line.isRequired) ...[
          const SizedBox(width: SdSpace.xs),
          StatusPill(text: l10n.docRequired, color: sd.leave),
        ],
      ]),
      subtitle: Text(sub, style: theme.textTheme.bodySmall),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (d != null && d.hasFiles && canOpen)
          IconButton(tooltip: l10n.docViewPdf, icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: busy ? null : onPdf),
        if (canEdit)
          PopupMenuButton<_Source>(
            tooltip: l10n.docAddPages,
            enabled: !busy,
            icon: const Icon(Icons.add_a_photo_outlined),
            onSelected: onAdd,
            itemBuilder: (_) => [
              for (final s in _sources)
                PopupMenuItem(
                  value: s,
                  child: Row(children: [Icon(_sourceIcon(s), size: 20), const SizedBox(width: SdSpace.sm), Text(_sourceLabel(l10n, s))]),
                ),
            ],
          ),
      ]),
    );
  }
}

/// Status and details of one document, and its pages (remove / reorder).
class _DocumentEditor extends ConsumerStatefulWidget {
  const _DocumentEditor({required this.line, required this.studentId, required this.canOpen});

  final DocumentLine line;
  final String studentId;
  final bool canOpen;

  @override
  ConsumerState<_DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends ConsumerState<_DocumentEditor> {
  late StudentDocument _doc =
      widget.line.document ?? StudentDocument(studentId: widget.studentId, typeKey: widget.line.type.key);
  late final _number = TextEditingController(text: _doc.number ?? '');
  late final _note = TextEditingController(text: _doc.note ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _number.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(documentRepositoryProvider).save(_doc.copyWith(number: _number.text, note: _note.text));
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        SdToast.show(context, AppLocalizations.of(context).saveFailed);
      }
    }
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final id = _doc.id;
    if (id == null) return;
    final ok = await SdDialog.confirm(
      context,
      title: l10n.docRemove,
      message: l10n.docRemoveConfirm,
      confirmLabel: l10n.docRemove,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok) return;
    await ref.read(documentRepositoryProvider).remove(id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final files = ref.watch(documentFilesProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(SdSpace.lg, 0, SdSpace.lg, SdSpace.xl),
          children: [
            Text(widget.line.type.label, style: theme.textTheme.titleLarge),
            const SizedBox(height: SdSpace.md),
            SegmentedButton<DocumentStatus>(
              segments: [
                for (final s in DocumentStatus.values) ButtonSegment(value: s, label: Text(docStatusLabel(l10n, s))),
              ],
              selected: {_doc.status},
              onSelectionChanged: (v) => setState(() => _doc = _doc.copyWith(status: v.first)),
            ),
            const SizedBox(height: SdSpace.md),
            TextField(controller: _number, decoration: InputDecoration(labelText: l10n.docNumber)),
            const SizedBox(height: SdSpace.sm),
            SdDateField(
              label: l10n.docIssuedOn,
              value: _doc.issuedOn,
              onChanged: (v) => setState(() => _doc = v == null ? _doc.copyWith(clearIssuedOn: true) : _doc.copyWith(issuedOn: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.docOriginalWithUs),
              value: _doc.isOriginal,
              onChanged: (v) => setState(() => _doc = _doc.copyWith(isOriginal: v)),
            ),
            if (_doc.isOriginal)
              SdDateField(
                label: l10n.docReturned,
                value: _doc.returnedOn,
                onChanged: (v) =>
                    setState(() => _doc = v == null ? _doc.copyWith(clearReturnedOn: true) : _doc.copyWith(returnedOn: v)),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.docVerifiedLabel),
              subtitle: Text(l10n.docVerifiedHint),
              value: _doc.verified,
              onChanged: (v) => setState(() => _doc = _doc.copyWith(verified: v)),
            ),
            TextField(controller: _note, decoration: InputDecoration(labelText: l10n.docNote), maxLines: 2),
            if (_doc.hasFiles) ...[
              const SizedBox(height: SdSpace.lg),
              Text(l10n.docPagesTitle, style: theme.textTheme.titleSmall),
              const SizedBox(height: SdSpace.sm),
              for (var i = 0; i < _doc.files.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: widget.canOpen && files != null && !DocumentFiles.isPdf(_doc.files[i])
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(SdRadius.sm),
                          child: Image.file(files.file(_doc.files[i]), width: 44, height: 56, fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined)),
                        )
                      : Icon(DocumentFiles.isPdf(_doc.files[i]) ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
                  title: Text(l10n.docPageN(i + 1)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: l10n.reportColumnUp,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      onPressed: i == 0
                          ? null
                          : () => setState(() {
                                final f = [..._doc.files];
                                f.insert(i - 1, f.removeAt(i));
                                _doc = _doc.copyWith(files: f);
                              }),
                    ),
                    IconButton(
                      tooltip: l10n.docRemovePage,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _doc = _doc.copyWith(files: [..._doc.files]..removeAt(i))),
                    ),
                  ]),
                ),
            ],
            const SizedBox(height: SdSpace.lg),
            Wrap(spacing: SdSpace.sm, runSpacing: SdSpace.sm, children: [
              SdButton(label: l10n.save, icon: Icons.check, onPressed: _saving ? null : _save),
              if (_doc.id != null)
                SdButton(label: l10n.docRemove, variant: SdButtonVariant.text, onPressed: _saving ? null : _remove),
            ]),
          ],
        ),
      ),
    );
  }
}

/// A PDF to look at, save, share or print.
class _PdfPage extends StatelessWidget {
  const _PdfPage({required this.title, required this.fileName, required this.bytes});

  final String title;
  final String fileName;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: l10n.reportSavePdf,
            icon: const Icon(Icons.download_outlined),
            onPressed: () async {
              final ok = await saveBytesWithDialog(fileName: '$fileName.pdf', bytes: bytes, title: l10n.reportSavePdf);
              if (ok && context.mounted) SdToast.show(context, l10n.exported);
            },
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        pdfFileName: '$fileName.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}
