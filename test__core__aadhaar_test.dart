import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/validation/aadhaar.dart';
import 'package:shiksha_desk/core/validation/mobile.dart';

String validAadhaar(String elevenDigits) => '$elevenDigits${Aadhaar.checkDigit(elevenDigits)}';

void main() {
  test('a number with the right check digit is accepted, with or without spaces', () {
    final number = validAadhaar('23456789012');
    expect(Aadhaar.isValid(number), isTrue);
    expect(Aadhaar.isValid(Aadhaar.format(number)), isTrue);
  });

  test('a single wrong digit or a swapped pair is caught', () {
    final number = validAadhaar('23456789012');
    final wrongDigit = '${number.substring(0, 5)}${(int.parse(number[5]) + 1) % 10}${number.substring(6)}';
    expect(Aadhaar.isValid(wrongDigit), isFalse);
    final swapped = '${number.substring(0, 3)}${number[4]}${number[3]}${number.substring(5)}';
    if (swapped != number) expect(Aadhaar.isValid(swapped), isFalse);
  });

  test('wrong length or a leading 0 or 1 is refused', () {
    expect(Aadhaar.isValid('12345'), isFalse);
    expect(Aadhaar.isValid(validAadhaar('13456789012')), isFalse);
  });

  test('masking shows only the last four digits', () {
    expect(Aadhaar.mask('9012'), 'XXXX XXXX 9012');
  });

  test('mobile numbers are normalised and checked', () {
    expect(MobileNumber.normalize('+91 98765 43210'), '9876543210');
    expect(MobileNumber.isValid('09876543210'), isTrue);
    expect(MobileNumber.isValid('12345'), isFalse);
    expect(MobileNumber.isValid('5876543210'), isFalse);
  });
}
