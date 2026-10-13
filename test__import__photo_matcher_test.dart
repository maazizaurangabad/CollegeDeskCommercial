import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shiksha_desk/modules/students/domain/student_models.dart';
import 'package:shiksha_desk/modules/students/import/photo_matcher.dart';
import 'package:shiksha_desk/modules/students/import/photo_resize.dart';

void main() {
  const students = [
    StudentKeys(id: 'a', fullName: 'Ayaan Salim Shaikh', displayCode: 'STU-000001', identifiers: {'gr': '45', 'pen': 'P-100'}, hasPhoto: false, divisionId: 'd1', rollNumber: 7),
    StudentKeys(id: 'b', fullName: 'Riya Patil', displayCode: 'STU-000002', identifiers: {'gr': '46'}, hasPhoto: true, divisionId: 'd1', rollNumber: 8),
    StudentKeys(id: 'c', fullName: 'Riya Patil', displayCode: 'STU-000003', identifiers: {'gr': '47'}, hasPhoto: false, divisionId: 'd2', rollNumber: 7),
  ];

  test('leading zeros, case, spaces and extensions are ignored', () {
    final matcher = PhotoMatcher(students);
    final m = matcher.match(['0045.JPG', '46.png', 'p 100.jpeg', '99.jpg'], PhotoKey.grNumber);
    expect(m[0].student?.id, 'a');
    expect(m[1].student?.id, 'b');
    expect(m[2].student, isNull);
    expect(m[3].student, isNull);
    expect(matcher.match(['P-100.jpg'], PhotoKey.pen).single.student?.id, 'a');
  });

  test('roll numbers only match inside the chosen division', () {
    final matcher = PhotoMatcher(students, divisionId: 'd2');
    expect(matcher.match(['7.jpg'], PhotoKey.rollInDivision).single.student?.id, 'c');
  });

  test('serial numbers come from an earlier Excel import', () {
    final matcher = PhotoMatcher(students, serials: {'1': 'b', '2': 'a'});
    expect(matcher.match(['1.jpg', '002.jpg'], PhotoKey.serialNo).map((m) => m.student?.id), ['b', 'a']);
  });

  test('names that fit two students are flagged, not guessed', () {
    final m = PhotoMatcher(students).match(['Riya Patil.jpg', 'ayaan salim shaikh.jpg'], PhotoKey.fullName);
    expect(m[0].ambiguous, isTrue);
    expect(m[1].student?.id, 'a');
  });

  test('student codes match with or without the STU prefix', () {
    final m = PhotoMatcher(students).match(['STU-000002.jpg', '000003.jpg'], PhotoKey.studentCode);
    expect(m.map((x) => x.student?.id), ['b', 'c']);
  });

  test('the suggested key is the one matching the most files', () {
    final (key, count) = PhotoMatcher(students).bestKey(['45.jpg', '46.jpg', '47.jpg']);
    expect(key, PhotoKey.grNumber);
    expect(count, 3);
  });

  test('large photos are resized to 600 px and saved as JPEG', () async {
    final big = img.Image(width: 1800, height: 2400);
    final resized = await resizeStudentPhoto(Uint8List.fromList(img.encodePng(big)));
    final decoded = img.decodeJpg(resized!)!;
    expect(decoded.height, 600);
    expect(decoded.width, 450);
    expect(await resizeStudentPhoto(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
