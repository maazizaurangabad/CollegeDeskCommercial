import 'package:flutter/foundation.dart';

import '../../../core/validation/mobile.dart';

/// What a message is about.
enum MessageKind {
  /// Absent on the day.
  absent,

  /// Absent several school days in a row.
  streak,

  /// The day's summary for staff (no single student).
  summary,

  /// Fees pending.
  feeDue,

  /// Exam result.
  result;

  static MessageKind byName(String name) => values.firstWhere((k) => k.name == name, orElse: () => absent);
}

/// The words that can be put in a template, and how they are written.
abstract final class MessagePlaceholders {
  static const student = '{student}';
  static const className = '{class}';
  static const roll = '{roll}';
  static const date = '{date}';
  static const days = '{days}';
  static const institution = '{institution}';
  static const mark = '{mark}';
  static const balance = '{balance}';
  static const overdue = '{overdue}';

  static const all = [student, className, roll, date, days, institution, mark, balance, overdue];

  /// Replaces every known placeholder; unknown words in braces are left as typed.
  static String fill(String template, Map<String, String> values) {
    var out = template;
    for (final e in values.entries) {
      out = out.replaceAll(e.key, e.value);
    }
    return out.trim();
  }
}

/// The institution's message settings.
@immutable
class MessageSettings {
  const MessageSettings({
    required this.absentTemplate,
    required this.streakTemplate,
    required this.streakDays,
    required this.codes,
    this.feeTemplate = defaultFeeTemplate,
  });

  static const defaultFeeTemplate = 'Dear Parent,\n'
      'Fees of {student} ({class}) are pending: {balance}.\n'
      'Please pay at the office at the earliest. Kindly ignore if already paid.\n'
      '- {institution}';

  /// The fee reminder text.
  final String feeTemplate;

  static const defaultAbsentTemplate = 'Dear Parent,\n'
      'This is to inform you that {student} ({class}) did not attend today, {date}.\n'
      'If this was not expected, please contact the office.\n'
      '- {institution}';

  static const defaultStreakTemplate = 'Dear Parent,\n'
      'This is to inform you that {student} ({class}) has not attended for the last {days} school days, up to {date}.\n'
      'Please contact the office at the earliest.\n'
      '- {institution}';

  static const defaultStreakDays = 3;

  final String absentTemplate;
  final String streakTemplate;

  /// From this many days in a row, the streak message is used.
  final int streakDays;

  /// Attendance marks that get a parent message (by default absent only, not leave).
  final Set<String> codes;
}

/// One phone number to message, with everyone it covers (siblings share one).
@immutable
class AbsentStudent {
  const AbsentStudent({
    required this.studentId,
    required this.fullName,
    required this.className,
    required this.divisionId,
    required this.code,
    required this.streak,
    this.rollNumber,
  });

  final String studentId;
  final String fullName;
  final String className;
  final String divisionId;
  final String code;

  /// Marked days in a row counted absent, up to the date.
  final int streak;
  final int? rollNumber;
}

/// A family to message: one number, one or more absent children.
@immutable
class AbsentFamily {
  const AbsentFamily({
    required this.students,
    required this.recipientName,
    required this.mobile,
    required this.kind,
    required this.body,
    this.sentAt,
  });

  final List<AbsentStudent> students;
  final String? recipientName;

  /// Ten digits, or null when no usable number is on record.
  final String? mobile;
  final MessageKind kind;

  /// The message, filled in from the template.
  final String body;

  /// When a message for this date was last opened; null if not yet.
  final DateTime? sentAt;

  bool get hasNumber => mobile != null;
  bool get isSent => sentAt != null;
  String get key => mobile ?? students.first.studentId;
  String get names => students.map((s) => s.fullName).join(', ');
}

/// A sent message as shown in history (siblings sent together are one record).
@immutable
class MessageRecord {
  const MessageRecord({
    required this.batchId,
    required this.kind,
    required this.forDate,
    required this.sentAt,
    required this.studentNames,
    required this.classNames,
    required this.body,
    required this.channel,
    required this.status,
    this.recipientName,
    this.mobile,
  });

  final String batchId;
  final MessageKind kind;
  final DateTime forDate;
  final DateTime sentAt;
  final List<String> studentNames;
  final List<String> classNames;
  final String body;
  final String channel;
  final String status;
  final String? recipientName;
  final String? mobile;
}

/// Builds WhatsApp links. A number is always sent with the India code.
abstract final class WhatsAppLink {
  /// Opens a chat with that number, message typed in.
  static Uri chat(String mobile, String text) =>
      Uri.parse('https://wa.me/91${MobileNumber.normalize(mobile)}?text=${Uri.encodeComponent(text)}');

  /// The same, through the WhatsApp desktop app (Windows).
  static Uri desktopChat(String mobile, String text) =>
      Uri.parse('whatsapp://send?phone=91${MobileNumber.normalize(mobile)}&text=${Uri.encodeComponent(text)}');

  /// Lets the user pick the chat or group (for the summary).
  static Uri pickChat(String text) => Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');

  static Uri desktopPickChat(String text) => Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}');
}
