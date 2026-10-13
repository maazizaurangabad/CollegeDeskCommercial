import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Shrinks a photo to at most 600 px on its longest side and saves it as
/// JPEG, in a background isolate so the screen stays smooth.
/// Returns null if the file is not a readable image.
Future<Uint8List?> resizeStudentPhoto(Uint8List bytes) {
  return Isolate.run(() {
    // A damaged or unknown file must never stop the whole photo import.
    try {
      return _resize(bytes);
    } catch (_) {
      return null;
    }
  });
}

Uint8List? _resize(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    final longest = oriented.width > oriented.height ? oriented.width : oriented.height;
    final resized = longest <= 600
        ? oriented
        : (oriented.width >= oriented.height
            ? img.copyResize(oriented, width: 600, interpolation: img.Interpolation.average)
            : img.copyResize(oriented, height: 600, interpolation: img.Interpolation.average));
    return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
}
