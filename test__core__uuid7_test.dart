import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/ids/uuid7.dart';

void main() {
  final pattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

  test('ids are valid version 7 UUIDs', () {
    for (var i = 0; i < 100; i++) {
      expect(Uuid7.generate(), matches(pattern));
    }
  });

  test('ids sort by creation time', () {
    final earlier = Uuid7.generate(DateTime.utc(2026, 1, 1));
    final later = Uuid7.generate(DateTime.utc(2026, 1, 2));
    expect(earlier.compareTo(later), lessThan(0));
  });

  test('ids do not repeat', () {
    final ids = {for (var i = 0; i < 5000; i++) Uuid7.generate()};
    expect(ids.length, 5000);
  });

  test('random keys have the requested length', () {
    expect(Uuid7.randomHex(32), matches(RegExp(r'^[0-9a-f]{64}$')));
  });
}
