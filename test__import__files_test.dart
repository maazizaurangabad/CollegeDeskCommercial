import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/files/csv.dart';
import 'package:shiksha_desk/core/files/xlsx.dart';
import 'package:shiksha_desk/core/validation/flexible_date.dart';

void main() {
  test('an .xlsx written by the app reads back exactly, including Marathi text and commas', () {
    final bytes = XlsxWriter.write(
      sheetName: 'Students',
      header: ['Sr No', 'Name of Student', 'मोबाईल'],
      rows: [
        ['1', 'Ayaan Salim Shaikh', '9876543210'],
        ['2', 'Patil, Riya & co <test>', ''],
      ],
    );
    expect(XlsxReader.sheetNames(bytes), ['Students']);
    final table = XlsxReader.readSheet(bytes, 0);
    expect(table.rows[0], ['Sr No', 'Name of Student', 'मोबाईल']);
    expect(table.rows[1], ['1', 'Ayaan Salim Shaikh', '9876543210']);
    expect(table.rows[2], ['2', 'Patil, Riya & co <test>', '']);
  });

  test('something that is not an .xlsx is refused clearly', () {
    expect(() => XlsxReader.sheetNames(utf8.encode('hello')), throwsFormatException);
  });

  test('CSV with quotes, commas, a BOM and semicolons is read correctly', () {
    final csv = utf8.encode('\uFEFFName,City\r\n"Shaikh, Ayaan",Pune\r\n"Say ""hi""",\r\n');
    expect(CsvReader.parse(csv), [
      ['Name', 'City'],
      ['Shaikh, Ayaan', 'Pune'],
      ['Say "hi"', ''],
    ]);
    expect(CsvReader.parse(utf8.encode('a;b\n1;2\n')), [
      ['a', 'b'],
      ['1', '2'],
    ]);
    final written = CsvReader.write(['A', 'B'], [
      ['x,y', 'z'],
    ]);
    expect(CsvReader.parse(written), [
      ['A', 'B'],
      ['x,y', 'z'],
    ]);
  });

  test('dates are read the Indian way, plus ISO and Excel serial numbers', () {
    final today = DateTime(2026, 10, 9);
    expect(FlexibleDate.parse('14/03/2010'), DateTime(2010, 3, 14));
    expect(FlexibleDate.parse('4-3-2010'), DateTime(2010, 3, 4));
    expect(FlexibleDate.parse('14.03.10', today: today), DateTime(2010, 3, 14));
    expect(FlexibleDate.parse('01/01/95', today: today), DateTime(1995, 1, 1));
    expect(FlexibleDate.parse('2010-03-14'), DateTime(2010, 3, 14));
    expect(FlexibleDate.parse('14 Mar 2010'), DateTime(2010, 3, 14));
    expect(FlexibleDate.parse('40251'), DateTime(2010, 3, 14));
    expect(FlexibleDate.parse('31/02/2010'), isNull);
    expect(FlexibleDate.parse('not a date'), isNull);
  });
}
