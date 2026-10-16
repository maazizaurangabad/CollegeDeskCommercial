import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/ids/uuid7.dart';

/// A file was too large to keep.
class DocumentTooLarge implements Exception {
  const DocumentTooLarge();
}

/// A file is not a photo or PDF the app can read.
class DocumentUnreadable implements Exception {
  const DocumentUnreadable();
}

/// Scanned pages, photos and PDFs of student documents, kept inside the
/// institution's media folder (so they are part of every backup) under
/// documents/STUDENT-ID/.
class DocumentFiles {
  DocumentFiles(this.mediaDir);

  final Directory mediaDir;

  static const maxPdfBytes = 10 * 1024 * 1024;

  /// A photo or scanned page: straightened and made smaller (about 300 KB).
  Future<String> addImage(String studentId, Uint8List bytes) async {
    final Uint8List jpeg;
    try {
      jpeg = await compute(compressDocumentImage, bytes);
    } catch (_) {
      throw const DocumentUnreadable();
    }
    return _write(studentId, 'jpg', jpeg);
  }

  /// A PDF, kept as it is (up to 10 MB).
  Future<String> addPdf(String studentId, Uint8List bytes) async {
    if (bytes.length > maxPdfBytes) throw const DocumentTooLarge();
    if (bytes.length < 5 || String.fromCharCodes(bytes.sublist(0, 5)) != '%PDF-') throw const DocumentUnreadable();
    return _write(studentId, 'pdf', bytes);
  }

  Future<String> _write(String studentId, String ext, Uint8List bytes) async {
    final relative = 'documents/$studentId/${Uuid7.generate()}.$ext';
    final file = File(p.join(mediaDir.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return relative;
  }

  File file(String relative) => File(p.join(mediaDir.path, relative));

  Future<Uint8List?> read(String relative) async {
    final f = file(relative);
    return await f.exists() ? f.readAsBytes() : null;
  }

  static bool isPdf(String relative) => relative.toLowerCase().endsWith('.pdf');
}

/// Phone photo -> upright JPEG, at most 1700 px on the long side.
Uint8List compressDocumentImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Not an image');
  final image = img.bakeOrientation(decoded);
  final long = math.max(image.width, image.height);
  final scaled = long <= 1700
      ? image
      : img.copyResize(
          image,
          width: image.width >= image.height ? 1700 : null,
          height: image.height > image.width ? 1700 : null,
          interpolation: img.Interpolation.average,
        );
  return Uint8List.fromList(img.encodeJpg(scaled, quality: 78));
}
