import 'package:flutter/foundation.dart';

import '../../results/domain/result_models.dart';

/// What happens to one student at the end of the year.
enum PromotionAction {
  /// Into the next class (e.g. 11th Science -> 12th Science).
  promote,

  /// Same class again next year (failed).
  repeat,

  /// Completed the last class (e.g. passed 12th): marked as left.
  leave,

  /// Nothing now; decide later (e.g. result not ready).
  skip,
}

/// How roll numbers are given in the new class.
enum RollOrder { byName, byGr, keep }

/// One student of the year being closed, with the suggested action.
class PromotionCandidate {
  PromotionCandidate({
    required this.studentId,
    required this.name,
    required this.fromDivisionId,
    required this.fromProgramId,
    required this.divisionName,
    required this.nextProgramId,
    required this.action,
    this.grNumber,
    this.roll,
    this.result,
  });

  final String studentId;
  final String name;
  final String? grNumber;
  final String fromDivisionId;
  final String fromProgramId;

  /// The division's name ("A"): the new class uses the same name.
  final String divisionName;
  final int? roll;

  /// Final result of the year; null when there is none.
  final ResultStatus? result;

  /// The class after this one; null for the last class.
  final String? nextProgramId;

  /// Chosen action (starts as the suggestion; the user may change it).
  PromotionAction action;

  bool get hasNext => nextProgramId != null;
  bool get noResult => result == null || result == ResultStatus.incomplete;

  /// Class for next year, or null when the student leaves / is skipped.
  String? get toProgramId => switch (action) {
        PromotionAction.promote => nextProgramId,
        PromotionAction.repeat => fromProgramId,
        PromotionAction.leave || PromotionAction.skip => null,
      };
}

/// The standard rule: passed (and ATKT, unless the institution says
/// otherwise) moves up, or leaves after the last class; failed repeats;
/// no final result yet moves up but is flagged (in the last class it waits,
/// since marking a student as passed out needs the result).
PromotionAction suggestedAction({required ResultStatus? result, required bool hasNext, bool promoteAtkt = true}) {
  final passed = result == ResultStatus.passed || (promoteAtkt && result == ResultStatus.atkt);
  if (result == ResultStatus.failed || (!promoteAtkt && result == ResultStatus.atkt)) return PromotionAction.repeat;
  if (passed) return hasNext ? PromotionAction.promote : PromotionAction.leave;
  return hasNext ? PromotionAction.promote : PromotionAction.skip;
}

/// Roll numbers for the students joining one class next year, after the
/// rolls already used there. [keep] keeps a student's old roll when free.
Map<String, int> assignRolls(
  List<PromotionCandidate> joining, {
  required RollOrder order,
  Set<int> taken = const {},
}) {
  final list = [...joining];
  int compareGr(PromotionCandidate a, PromotionCandidate b) {
    final x = int.tryParse(a.grNumber ?? ''), y = int.tryParse(b.grNumber ?? '');
    if (x != null && y != null) return x.compareTo(y);
    if (x != null) return -1;
    if (y != null) return 1;
    return (a.grNumber ?? '').compareTo(b.grNumber ?? '');
  }

  switch (order) {
    case RollOrder.byName:
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    case RollOrder.byGr:
      list.sort((a, b) {
        final c = compareGr(a, b);
        return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    case RollOrder.keep:
      list.sort((a, b) => (a.roll ?? 1 << 30).compareTo(b.roll ?? 1 << 30));
  }
  final used = {...taken};
  final out = <String, int>{};
  var next = (used.isEmpty ? 0 : used.reduce((a, b) => a > b ? a : b)) + 1;
  if (order == RollOrder.keep) {
    for (final c in list) {
      final r = c.roll;
      if (r != null && r > 0 && !used.contains(r)) {
        out[c.studentId] = r;
        used.add(r);
      }
    }
    next = (used.isEmpty ? 0 : used.reduce((a, b) => a > b ? a : b)) + 1;
  }
  for (final c in list) {
    if (out.containsKey(c.studentId)) continue;
    while (used.contains(next)) {
      next++;
    }
    out[c.studentId] = next;
    used.add(next);
  }
  return out;
}

/// What a promotion did.
@immutable
class PromotionResult {
  const PromotionResult({
    required this.batchId,
    required this.promoted,
    required this.repeated,
    required this.left,
    required this.skipped,
    this.feesCopied = 0,
  });

  final String batchId;
  final int promoted;
  final int repeated;
  final int left;
  final int skipped;
  final int feesCopied;
}

/// One past promotion, for the history list (with undo).
@immutable
class PromotionBatch {
  const PromotionBatch({
    required this.id,
    required this.label,
    required this.createdAt,
    required this.promoted,
    required this.repeated,
    required this.left,
    required this.undone,
  });

  final String id;
  final String label;
  final DateTime createdAt;
  final int promoted;
  final int repeated;
  final int left;
  final bool undone;
}
