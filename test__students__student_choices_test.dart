import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/modules/students/domain/student_models.dart';

void main() {
  test('height choices show feet, inches and centimetres', () {
    final options = StudentChoices.heightOptions();
    expect(options.first, (91.0, '3 ft (91 cm)'));
    expect(options.last, (213.0, '7 ft (213 cm)'));
    expect(options, contains((168.0, '5 ft 6 in (168 cm)')));
    expect(options, contains((183.0, '6 ft (183 cm)')));
    // One choice per inch, all different.
    expect(options.map((o) => o.$1).toSet(), hasLength(options.length));
  });

  test('a height typed earlier is still shown sensibly', () {
    expect(StudentChoices.heightLabel(165), '5 ft 5 in (165 cm)');
    expect(StudentChoices.heightLabel(165.5), '5 ft 5 in (165.5 cm)');
    expect(StudentChoices.heightLabel(null), isNull);
  });

  test('weight choices', () {
    expect(StudentChoices.weightOptions().first, (10.0, '10 kg'));
    expect(StudentChoices.weightLabel(52.5), '52.5 kg');
  });
}
