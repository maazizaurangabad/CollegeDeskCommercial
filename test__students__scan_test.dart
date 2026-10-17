import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shiksha_desk/modules/students/documents/scan_processing.dart';

/// A dark table with a white page (with a black line of "text") on it.
Uint8List _photo() {
  final image = img.Image(width: 400, height: 300);
  img.fill(image, color: img.ColorRgb8(40, 40, 40));
  img.fillRect(image, x1: 100, y1: 50, x2: 300, y2: 250, color: img.ColorRgb8(230, 230, 225));
  img.fillRect(image, x1: 130, y1: 140, x2: 270, y2: 150, color: img.ColorRgb8(20, 20, 20));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  test('finds the page and straightens it to its own size', () {
    final photo = prepareScanPhoto(_photo());
    expect((photo.width, photo.height), (400, 300));
    final corners = guessCorners(photo.jpeg);
    expect(corners[0].$1, closeTo(0.25, 0.04));
    expect(corners[0].$2, closeTo(1 / 6, 0.04));
    expect(corners[2].$1, closeTo(0.75, 0.04));
    expect(corners[2].$2, closeTo(5 / 6, 0.04));

    final page = img.decodeJpg(processScan(ScanJob(photo.jpeg, corners, ScanFilter.colour)))!;
    expect(page.width, closeTo(200, 12));
    expect(page.height, closeTo(200, 12));
  });

  test('clean: paper becomes white and writing black', () {
    final photo = prepareScanPhoto(_photo());
    final corners = guessCorners(photo.jpeg);
    final page = img.decodeJpg(processScan(ScanJob(photo.jpeg, corners, ScanFilter.clean)))!;
    final paper = page.getPixel(20, 20).r;
    final text = page.getPixel(page.width ~/ 2, (page.height * 0.47).round()).r;
    expect(paper, greaterThan(230));
    expect(text, lessThan(60));
  });

  test('no clear page: a frame just inside the photo', () {
    final plain = img.Image(width: 200, height: 200);
    img.fill(plain, color: img.ColorRgb8(128, 128, 128));
    final corners = guessCorners(Uint8List.fromList(img.encodeJpg(plain)));
    expect(corners.first, (0.06, 0.06));
  });

  test('rotating turns width into height', () {
    final photo = prepareScanPhoto(_photo());
    final turned = rotateScanPhoto(photo.jpeg);
    expect((turned.width, turned.height), (300, 400));
  });
}
