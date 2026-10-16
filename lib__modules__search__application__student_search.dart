import '../../students/data/student_repository.dart';
import '../../students/domain/student_models.dart';
import '../../students/presentation/student_picker.dart';

/// A roll / seat number typed alone (1 to 4 digits).
int? rollQuery(String query) {
  final q = query.trim();
  return RegExp(r'^\d{1,4}$').hasMatch(q) ? int.parse(q) : null;
}

/// Finds students for the search screen. Text matches name, code, G.R.,
/// PEN, APAAR, Saral ID, admission number, parents' names and mobiles and
/// the institution's own fields (never Aadhaar). A number alone also finds
/// that roll number in [academicYearId]. With no text but a class chosen,
/// the whole class is listed by roll. No limit on how many are found.
Future<List<StudentListItem>> searchStudents(
  StudentRepository repo, {
  required String query,
  String? academicYearId,
  Set<String>? divisionIds,
  StudentStatus? status,
}) async {
  final q = query.trim();
  final byText = q.isEmpty ? const <StudentListItem>[] : await repo.list(query: q, academicYearId: academicYearId, status: status);
  final needAll = rollQuery(q) != null || (q.isEmpty && divisionIds != null);
  final all = needAll ? await repo.list(academicYearId: academicYearId, status: status) : const <StudentListItem>[];
  return mergeSearch(query: q, byText: byText, all: all, divisionIds: divisionIds);
}

/// Roll-number matches first, then text matches; each student once; only
/// the chosen classes. With no text, everyone in the chosen classes by roll.
List<StudentListItem> mergeSearch({
  required String query,
  required List<StudentListItem> byText,
  required List<StudentListItem> all,
  Set<String>? divisionIds,
}) {
  final roll = rollQuery(query);
  final out = <StudentListItem>[];
  final seen = <String>{};
  bool inClass(StudentListItem s) => divisionIds == null || divisionIds.contains(s.divisionId);
  void add(StudentListItem s) {
    if (inClass(s) && seen.add(s.id)) out.add(s);
  }

  if (roll != null) {
    for (final s in sortStudents(all.where((s) => s.rollNumber == roll).toList(), StudentSort.name)) {
      add(s);
    }
  }
  byText.forEach(add);
  if (query.trim().isEmpty && divisionIds != null) {
    sortStudents(all, StudentSort.roll).forEach(add);
  }
  return out;
}
