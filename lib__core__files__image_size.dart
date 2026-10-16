import 'dart:typed_data';

/// Width and height in pixels of a JPEG or PNG, read from its header only.
/// Null when the bytes are neither, or the header is damaged.
({int width, int height})? imagePixelSize(Uint8List b) {
  // PNG: 8-byte signature, then the IHDR chunk with width and height.
  if (b.length >= 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    final width = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
    final height = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
    return width > 0 && height > 0 ? (width: width, height: height) : null;
  }
  // JPEG: walk the segments to a start-of-frame marker.
  if (b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      // Markers without a length.
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
        i += 2;
        continue;
      }
      final length = (b[i + 2] << 8) | b[i + 3];
      final isFrame = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
      if (isFrame) {
        final height = (b[i + 5] << 8) | b[i + 6];
        final width = (b[i + 7] << 8) | b[i + 8];
        return width > 0 && height > 0 ? (width: width, height: height) : null;
      }
      if (length < 2) return null;
      i += 2 + length;
    }
  }
  return null;
}

/// The size of a picture fitted inside a [boxWidth] × [boxHeight] box,
/// keeping its shape. Any unit (points, EMU).
({double width, double height}) fitInBox(({int width, int height})? pixels, double boxWidth, double boxHeight) {
  if (pixels == null) return (width: boxWidth, height: boxHeight);
  final scale = [boxWidth / pixels.width, boxHeight / pixels.height].reduce((a, b) => a < b ? a : b);
  return (width: pixels.width * scale, height: pixels.height * scale);
}

/// "jpeg" or "png" for a picture's file name and content type; null otherwise.
String? imageKind(Uint8List b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'jpeg';
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
  return null;
}
