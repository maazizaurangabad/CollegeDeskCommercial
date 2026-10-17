import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'scan_processing.dart';

/// Scans one or more pages with Shiksha Desk's own scanner: take a photo
/// (or choose a picture on a computer), drag the four corners onto the
/// page, then keep it cleaned up. Works on every phone; nothing from
/// Google Play Services is needed. Returns the finished pages (JPEG).
Future<List<Uint8List>> runDocumentScan(BuildContext context) async {
  final pages = <Uint8List>[];
  while (true) {
    final raw = await _capture();
    if (raw == null || !context.mounted) break;
    final result = await Navigator.of(context).push<_EditorResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ScanEditor(raw: raw, pageNumber: pages.length + 1),
      ),
    );
    if (result == null) break;
    if (result.retake) continue;
    pages.add(result.page!);
    if (!result.another) break;
  }
  return pages;
}

/// A photo from the camera (phones) or a picture file (computers).
Future<Uint8List?> _capture() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final shot = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 3000, imageQuality: 95);
    return shot == null ? null : await shot.readAsBytes();
  }
  final picked = await FilePicker.platform.pickFiles(type: FileType.image);
  final path = picked?.files.firstOrNull?.path;
  return path == null ? null : await File(path).readAsBytes();
}

class _EditorResult {
  const _EditorResult.retake()
      : retake = true,
        page = null,
        another = false;
  const _EditorResult.page(Uint8List this.page, {required this.another}) : retake = false;

  final bool retake;
  final Uint8List? page;
  final bool another;
}

class _ScanEditor extends StatefulWidget {
  const _ScanEditor({required this.raw, required this.pageNumber});

  final Uint8List raw;
  final int pageNumber;

  @override
  State<_ScanEditor> createState() => _ScanEditorState();
}

class _ScanEditorState extends State<_ScanEditor> {
  ScanPhoto? _photo;

  /// Page corners as fractions: top-left, top-right, bottom-right, bottom-left.
  List<Offset> _corners = const [Offset(0.06, 0.06), Offset(0.94, 0.06), Offset(0.94, 0.94), Offset(0.06, 0.94)];
  ScanFilter _filter = ScanFilter.clean;
  Uint8List? _result;
  bool _working = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load(() => compute(prepareScanPhoto, widget.raw));
  }

  Future<void> _load(Future<ScanPhoto> Function() make) async {
    setState(() {
      _working = true;
      _failed = false;
    });
    try {
      final photo = await make();
      final guess = await compute(guessCorners, photo.jpeg);
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _corners = [for (final (x, y) in guess) Offset(x, y)];
        _working = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _working = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _process() async {
    final photo = _photo;
    if (photo == null) return;
    setState(() => _working = true);
    try {
      final out = await compute(
        processScan,
        ScanJob(photo.jpeg, [for (final c in _corners) (c.dx, c.dy)], _filter),
      );
      if (!mounted) return;
      setState(() {
        _result = out;
        _working = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
      SdToast.show(context, AppLocalizations.of(context).scanFailed);
    }
  }

  void _setFilter(ScanFilter f) {
    if (f == _filter) return;
    _filter = f;
    _process();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final photo = _photo;
    final result = _result;

    Widget body;
    if (_failed) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(SdSpace.xl),
          child: Text(l10n.docUnreadable, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        ),
      );
    } else if (photo == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (result != null) {
      body = InteractiveViewer(
        maxScale: 5,
        child: Center(child: Image.memory(result, gaplessPlayback: true)),
      );
    } else {
      body = _CornerEditor(
        photo: photo,
        corners: _corners,
        color: theme.colorScheme.primary,
        onChanged: (c) => setState(() => _corners = c),
      );
    }

    final buttons = <Widget>[
      if (result == null) ...[
        TextButton.icon(
          onPressed: _working ? null : () => Navigator.of(context).pop(const _EditorResult.retake()),
          icon: const Icon(Icons.replay),
          label: Text(l10n.scanRetake),
        ),
        TextButton.icon(
          onPressed: _working || photo == null ? null : () => _load(() => compute(rotateScanPhoto, photo.jpeg)),
          icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
          label: Text(l10n.scanRotate),
        ),
        FilledButton.icon(
          onPressed: _working || photo == null ? null : _process,
          icon: const Icon(Icons.crop_free),
          label: Text(l10n.scanNext),
        ),
      ] else ...[
        TextButton.icon(
          onPressed: _working ? null : () => setState(() => _result = null),
          icon: const Icon(Icons.crop),
          label: Text(l10n.scanAdjust),
        ),
        OutlinedButton.icon(
          onPressed: _working ? null : () => Navigator.of(context).pop(_EditorResult.page(result, another: true)),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(l10n.scanSaveAndNext),
        ),
        FilledButton.icon(
          onPressed: _working ? null : () => Navigator.of(context).pop(_EditorResult.page(result, another: false)),
          icon: const Icon(Icons.check),
          label: Text(l10n.scanSave),
        ),
      ],
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.scanPageTitle(widget.pageNumber)),
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SdSpace.lg, 0, SdSpace.lg, SdSpace.sm),
            child: Text(
              result == null ? l10n.scanAdjustHint : l10n.scanCheckHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: body),
              if (_working && photo != null)
                const Positioned.fill(
                  child: ColoredBox(color: Color(0x66000000), child: Center(child: CircularProgressIndicator())),
                ),
            ]),
          ),
          if (result != null)
            Padding(
              padding: const EdgeInsets.only(top: SdSpace.sm),
              child: SegmentedButton<ScanFilter>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  foregroundColor: Colors.white,
                  selectedForegroundColor: Colors.black,
                  selectedBackgroundColor: Colors.white,
                ),
                segments: [
                  ButtonSegment(value: ScanFilter.clean, label: Text(l10n.scanFilterClean)),
                  ButtonSegment(value: ScanFilter.grey, label: Text(l10n.scanFilterGrey)),
                  ButtonSegment(value: ScanFilter.colour, label: Text(l10n.scanFilterColour)),
                ],
                selected: {_filter},
                onSelectionChanged: _working ? null : (s) => _setFilter(s.first),
              ),
            ),
          Theme(
            data: theme.copyWith(
              textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Colors.white)),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(SdSpace.md),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: SdSpace.sm,
                runSpacing: SdSpace.sm,
                children: buttons,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The photo with four corner handles to drag onto the page's corners.
class _CornerEditor extends StatelessWidget {
  const _CornerEditor({required this.photo, required this.corners, required this.color, required this.onChanged});

  final ScanPhoto photo;
  final List<Offset> corners;
  final Color color;
  final ValueChanged<List<Offset>> onChanged;

  static const _handle = 48.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const pad = _handle / 2;
      final availW = box.maxWidth - pad * 2, availH = box.maxHeight - pad * 2;
      final ratio = photo.width / photo.height;
      var w = availW, h = availW / ratio;
      if (h > availH) {
        h = availH;
        w = availH * ratio;
      }
      final rect = Rect.fromLTWH((box.maxWidth - w) / 2, (box.maxHeight - h) / 2, w, h);
      Offset toScreen(Offset f) => Offset(rect.left + f.dx * rect.width, rect.top + f.dy * rect.height);

      return Stack(children: [
        Positioned.fromRect(
          rect: rect,
          child: Image.memory(
            photo.jpeg,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            cacheWidth: photo.width >= photo.height ? 1400 : null,
            cacheHeight: photo.width < photo.height ? 1400 : null,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _QuadPainter([for (final c in corners) toScreen(c)], color)),
          ),
        ),
        for (var i = 0; i < 4; i++)
          Positioned(
            left: toScreen(corners[i]).dx - _handle / 2,
            top: toScreen(corners[i]).dy - _handle / 2,
            width: _handle,
            height: _handle,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) {
                final next = [...corners];
                final c = next[i] + Offset(d.delta.dx / rect.width, d.delta.dy / rect.height);
                next[i] = Offset(c.dx.clamp(0.0, 1.0), c.dy.clamp(0.0, 1.0));
                onChanged(next);
              },
              child: Center(
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.points, this.color);

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter old) => old.points != points || old.color != color;
}
