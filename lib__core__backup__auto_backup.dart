import 'dart:io';

import 'package:path/path.dart' as p;

/// Rules for the automatic backups kept on the device:
/// the newest 7 daily ones, plus one per week for the 4 weeks before that.
/// "before-…" backups (taken before an import or restore) are kept 30 days.
abstract final class AutoBackupPolicy {
  static String dailyName(DateTime day) =>
      'auto-${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}.sdbak';

  static String beforeName(String reason, DateTime at) =>
      'before-$reason-${at.toUtc().toIso8601String().replaceAll(':', '-').split('.').first}.sdbak';

  static DateTime? dayOf(String fileName) {
    final m = RegExp(r'^auto-(\d{4})-(\d{2})-(\d{2})\.sdbak$').firstMatch(fileName);
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  /// File names to delete from [names], given today's date.
  static List<String> toDelete(List<String> names, DateTime today, {Map<String, DateTime>? modified}) {
    final daily = names.where((n) => dayOf(n) != null).toList()..sort((a, b) => b.compareTo(a));
    final keep = <String>{...daily.take(7)};
    final weeks = <int>{};
    for (final n in daily.skip(7)) {
      final day = dayOf(n)!;
      final age = DateTime(today.year, today.month, today.day).difference(day).inDays;
      final week = age ~/ 7;
      if (age <= 35 && weeks.add(week) && weeks.length <= 4) keep.add(n);
    }
    final deletions = daily.where((n) => !keep.contains(n)).toList();
    for (final n in names.where((n) => n.startsWith('before-'))) {
      final m = modified?[n];
      if (m != null && today.difference(m).inDays > 30) deletions.add(n);
    }
    return deletions;
  }

  static Directory folderFor(Directory supportDir, String workspaceId) =>
      Directory(p.join(supportDir.path, 'backups', workspaceId, 'auto'));
}
