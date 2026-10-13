import 'package:path/path.dart' as p;

import '../domain/student_models.dart';

/// What a photo's file name stands for.
enum PhotoKey { serialNo, grNumber, admissionNumber, studentCode, pen, apaar, saralId, rollInDivision, fullName }

class PhotoMatch {
  PhotoMatch({required this.fileName, this.student, this.ambiguous = false});

  final String fileName;
  final StudentKeys? student;

  /// More than one student fits (e.g. two students with the same name).
  final bool ambiguous;
}

/// Matches photo file names to students. Case, spaces, dashes, leading
/// zeros and the extension are ignored: "0045.JPG" matches GR "45".
class PhotoMatcher {
  PhotoMatcher(this.students, {this.serials = const {}, this.divisionId});

  final List<StudentKeys> students;

  /// Serial number -> student id, from an earlier Excel import.
  final Map<String, String> serials;

  /// Needed for [PhotoKey.rollInDivision].
  final String? divisionId;

  static String normalize(String value) {
    var v = value.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-./]'), '');
    if (RegExp(r'^\d+$').hasMatch(v)) v = v.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return v;
  }

  static String baseName(String fileName) => p.basenameWithoutExtension(fileName);

  Map<String, List<StudentKeys>> _index(PhotoKey key) {
    final index = <String, List<StudentKeys>>{};
    void add(String? value, StudentKeys s) {
      if (value == null || value.trim().isEmpty) return;
      (index[normalize(value)] ??= []).add(s);
    }

    final byId = {for (final s in students) s.id: s};
    switch (key) {
      case PhotoKey.serialNo:
        for (final e in serials.entries) {
          final s = byId[e.value];
          if (s != null) add(e.key, s);
        }
      case PhotoKey.rollInDivision:
        for (final s in students.where((s) => s.divisionId == divisionId && divisionId != null)) {
          add(s.rollNumber?.toString(), s);
        }
      case PhotoKey.studentCode:
        for (final s in students) {
          add(s.displayCode, s);
          add(s.displayCode.replaceFirst(RegExp(r'^STU-?', caseSensitive: false), ''), s);
        }
      case PhotoKey.fullName:
        for (final s in students) {
          add(s.fullName, s);
        }
      default:
        final code = _identifierCode(key);
        for (final s in students) {
          add(s.identifiers[code], s);
        }
    }
    return index;
  }

  static String _identifierCode(PhotoKey key) => switch (key) {
        PhotoKey.grNumber => IdentifierType.grNumber.code,
        PhotoKey.admissionNumber => IdentifierType.admissionNumber.code,
        PhotoKey.pen => IdentifierType.pen.code,
        PhotoKey.apaar => IdentifierType.apaar.code,
        PhotoKey.saralId => IdentifierType.saralId.code,
        _ => '',
      };

  List<PhotoMatch> match(List<String> fileNames, PhotoKey key) {
    final index = _index(key);
    return [
      for (final f in fileNames)
        () {
          final hits = index[normalize(baseName(f))] ?? const [];
          if (hits.length == 1) return PhotoMatch(fileName: f, student: hits.single);
          return PhotoMatch(fileName: f, ambiguous: hits.length > 1);
        }(),
    ];
  }

  /// The key that matches the most files, with how many it matched.
  (PhotoKey, int) bestKey(List<String> fileNames) {
    var best = (PhotoKey.grNumber, -1);
    for (final key in PhotoKey.values) {
      if (key == PhotoKey.serialNo && serials.isEmpty) continue;
      if (key == PhotoKey.rollInDivision && divisionId == null) continue;
      final count = match(fileNames, key).where((m) => m.student != null).length;
      if (count > best.$2) best = (key, count);
    }
    return best;
  }
}
