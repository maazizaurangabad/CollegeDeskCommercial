import 'package:flutter/foundation.dart';

/// How a payment was made.
enum PaymentMode {
  cash,
  upi,
  cheque,
  bank;

  static PaymentMode byName(String name) => values.firstWhere((m) => m.name == name, orElse: () => cash);

  /// Cash needs no reference; the others usually have a transaction or cheque number.
  bool get needsReference => this != cash;
}

@immutable
class FeeHead {
  const FeeHead({required this.id, required this.name, required this.displayOrder, required this.isActive});

  final String id;
  final String name;
  final int displayOrder;
  final bool isActive;
}

/// What one class pays in a year, for everyone or for one category.
@immutable
class FeeStructure {
  const FeeStructure({
    required this.id,
    required this.academicYearId,
    required this.programId,
    required this.amounts,
    this.category,
  });

  final String id;
  final String academicYearId;
  final String programId;

  /// null: every student of the class (unless a category structure applies).
  final String? category;

  /// headId -> amount (whole rupees). Heads with no amount are left out.
  final Map<String, int> amounts;

  int get total => amounts.values.fold(0, (a, b) => a + b);
}

/// An installment: by [dueDate], [amount] in total should have been paid.
@immutable
class FeeDueDate {
  const FeeDueDate({required this.label, required this.dueDate, required this.amount});

  final String label;
  final DateTime dueDate;

  /// Cumulative: everything to be paid by this date, not just this installment.
  final int amount;
}

/// Amount that should have been paid by [today] under these installments.
/// Without installments the whole amount is due at once.
int dueBy(List<FeeDueDate> dates, DateTime today, int total) {
  if (dates.isEmpty) return total;
  final day = DateTime(today.year, today.month, today.day);
  var amount = 0;
  for (final d in dates) {
    final due = DateTime(d.dueDate.year, d.dueDate.month, d.dueDate.day);
    if (!due.isAfter(day) && d.amount > amount) amount = d.amount;
  }
  return amount > total ? total : amount;
}

/// One student's fee position for a year, in lists and reports.
@immutable
class StudentFeeBalance {
  const StudentFeeBalance({
    required this.studentId,
    required this.name,
    required this.classLabel,
    required this.divisionId,
    required this.programId,
    required this.due,
    required this.paid,
    required this.dueByToday,
    this.rollNumber,
    this.category,
    this.mobile,
  });

  final String studentId;
  final String name;
  final String classLabel;
  final String divisionId;
  final String programId;
  final int? rollNumber;
  final String? category;
  final String? mobile;
  final int due;
  final int paid;

  /// What should have been paid by today (installments), at most [due].
  final int dueByToday;

  int get balance => due - paid;
  int get overdue => dueByToday - paid > 0 ? dueByToday - paid : 0;
}

@immutable
class FeeAdjustment {
  const FeeAdjustment({
    required this.id,
    required this.headId,
    required this.headName,
    required this.amount,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String headId;
  final String headName;

  /// Negative: concession. Positive: extra charge.
  final int amount;
  final String reason;
  final DateTime createdAt;
}

/// One head on a student's account.
@immutable
class FeeLine {
  const FeeLine({
    required this.headId,
    required this.headName,
    required this.fromStructure,
    required this.adjustment,
    required this.paid,
  });

  final String headId;
  final String headName;
  final int fromStructure;
  final int adjustment;
  final int paid;

  int get due => fromStructure + adjustment < 0 ? 0 : fromStructure + adjustment;
  int get balance => due - paid;
}

@immutable
class FeeReceiptLine {
  const FeeReceiptLine({required this.headId, required this.headName, required this.amount});

  final String headId;
  final String headName;
  final int amount;
}

enum ReceiptStatus { issued, cancelled }

@immutable
class FeeReceiptRecord {
  const FeeReceiptRecord({
    required this.id,
    required this.serialLabel,
    required this.academicYearId,
    required this.academicYearLabel,
    required this.studentId,
    required this.studentName,
    required this.classLabel,
    required this.receivedOn,
    required this.total,
    required this.mode,
    required this.status,
    required this.lines,
    required this.printCount,
    required this.createdAt,
    this.grNumber,
    this.balanceAfter,
    this.reference,
    this.note,
    this.cancelReason,
    this.createdBy,
  });

  /// User id of whoever issued the receipt (for "Issued by").
  final String? createdBy;

  final String id;
  final String serialLabel;
  final String academicYearId;
  final String academicYearLabel;
  final String studentId;
  final String studentName;
  final String classLabel;
  final String? grNumber;
  final DateTime receivedOn;
  final int total;
  final int? balanceAfter;
  final PaymentMode mode;
  final String? reference;
  final String? note;
  final ReceiptStatus status;
  final String? cancelReason;
  final List<FeeReceiptLine> lines;
  final int printCount;
  final DateTime createdAt;

  bool get isCancelled => status == ReceiptStatus.cancelled;
}

/// A student's fees for one academic year.
@immutable
class FeeAccount {
  const FeeAccount({
    required this.studentId,
    required this.studentName,
    required this.academicYearId,
    required this.academicYearLabel,
    required this.lines,
    required this.adjustments,
    required this.receipts,
    this.classLabel = '',
    this.grNumber,
    this.programId,
    this.category,
    this.structureId,
    this.structureCategory,
    this.dueDates = const [],
    this.today,
  });

  /// Installments of the structure applied (may be empty).
  final List<FeeDueDate> dueDates;

  /// The day [overdue] is worked out for.
  final DateTime? today;

  final String studentId;
  final String studentName;
  final String academicYearId;
  final String academicYearLabel;
  final String classLabel;
  final String? grNumber;
  final String? programId;
  final String? category;

  /// The structure applied (null when the class has none for the year).
  final String? structureId;

  /// Category of that structure; null means the class's general one.
  final String? structureCategory;

  /// In fee head order.
  final List<FeeLine> lines;
  final List<FeeAdjustment> adjustments;

  /// Newest first, cancelled ones included.
  final List<FeeReceiptRecord> receipts;

  int get due => lines.fold(0, (a, l) => a + l.due);
  int get paid => lines.fold(0, (a, l) => a + l.paid);
  int get balance => due - paid;
  bool get hasStructure => structureId != null;

  /// Of the balance, what is past its installment date.
  int get overdue {
    final by = dueBy(dueDates, today ?? DateTime.now(), due);
    return by - paid > 0 ? by - paid : 0;
  }

  /// The next installment not yet reached, if any.
  FeeDueDate? get nextDue {
    final t = today ?? DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final later = dueDates.where((d) => DateTime(d.dueDate.year, d.dueDate.month, d.dueDate.day).isAfter(day)).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return later.firstOrNull;
  }

  /// Shares [amount] over the heads in order, filling each balance.
  /// What cannot be placed is returned as [rest] (more than is due).
  ({Map<String, int> byHead, int rest}) allocate(int amount) {
    var left = amount < 0 ? 0 : amount;
    final out = <String, int>{};
    for (final l in lines) {
      if (left <= 0) break;
      if (l.balance <= 0) continue;
      final take = l.balance < left ? l.balance : left;
      out[l.headId] = take;
      left -= take;
    }
    return (byHead: out, rest: left);
  }
}

enum FeeIssue { emptyName, duplicateName, headInUse, noAmount, negativeAmount, noStudentYear, notFound, futureDate, noReason }

class FeeException implements Exception {
  const FeeException(this.issue, [this.detail]);

  final FeeIssue issue;
  final String? detail;

  @override
  String toString() => 'FeeException(${issue.name})';
}

/// Rupee amounts written the Indian way: 1,25,000 and "One Lakh Twenty Five Thousand".
abstract final class Rupees {
  /// 125000 -> "1,25,000"
  static String format(int amount) {
    final negative = amount < 0;
    final digits = amount.abs().toString();
    if (digits.length <= 3) return '${negative ? '-' : ''}$digits';
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${negative ? '-' : ''}${parts.join(',')},$last3';
  }

  static const _ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', //
    'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
  ];
  static const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

  static String _below100(int n) => n < 20 ? _ones[n] : '${_tens[n ~/ 10]} ${_ones[n % 10]}'.trim();

  static String _below1000(int n) {
    final h = n ~/ 100;
    final r = n % 100;
    return [if (h > 0) '${_ones[h]} Hundred', if (r > 0) _below100(r)].join(' ');
  }

  /// 125000 -> "Rupees One Lakh Twenty Five Thousand Only"
  static String words(int amount) {
    var n = amount.abs();
    if (n == 0) return 'Rupees Zero Only';
    final parts = <String>[];
    final crore = n ~/ 10000000;
    n %= 10000000;
    final lakh = n ~/ 100000;
    n %= 100000;
    final thousand = n ~/ 1000;
    n %= 1000;
    if (crore > 0) parts.add('${crore >= 1000 ? words(crore).replaceAll('Rupees ', '').replaceAll(' Only', '') : _below1000(crore)} Crore');
    if (lakh > 0) parts.add('${_below100(lakh)} Lakh');
    if (thousand > 0) parts.add('${_below100(thousand)} Thousand');
    if (n > 0) parts.add(_below1000(n));
    return 'Rupees ${parts.join(' ')} Only';
  }
}
