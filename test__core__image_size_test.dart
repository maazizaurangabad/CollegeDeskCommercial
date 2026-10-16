import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shiksha_desk/core/files/image_size.dart';

void main() {
  test('reads the size of JPEG and PNG photos', () {
    final photo = img.Image(width: 413, height: 531);
    expect(imagePixelSize(Uint8List.fromList(img.encodeJpg(photo))), (width: 413, height: 531));
    expect(imagePixelSize(Uint8List.fromList(img.encodePng(photo))), (width: 413, height: 531));
    expect(imageKind(Uint8List.fromList(img.encodePng(photo))), 'png');
    expect(imagePixelSize(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
  });

  test('a photo is fitted inside its box without stretching', () {
    final fit = fitInBox((width: 400, height: 400), 48, 60);
    expect(fit.width, 48);
    expect(fit.height, 48);
    final tall = fitInBox((width: 413, height: 531), 48, 60);
    expect(tall.height, closeTo(60, 0.001));
    expect(tall.width, lessThan(48));
  });
}
