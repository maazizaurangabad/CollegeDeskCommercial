import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_models.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/reporting/report_dataset.dart';
import '../../attendance/application/attendance_providers.dart';
import '../../students/application/students_providers.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => MessageRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(sessionProvider),
    ref.watch(appSettingsRepositoryProvider),
    ref.watch(attendanceRepositoryProvider),
    ref.watch(studentRepositoryProvider),
  ),
);

/// Bumped after a message is recorded or the templates change.
final messagesRevisionProvider = StateProvider<int>((ref) => 0);

final messageSettingsProvider = FutureProvider<MessageSettings>((ref) {
  ref.watch(messagesRevisionProvider);
  ref.watch(attendanceRevisionProvider);
  return ref.watch(messageRepositoryProvider).loadSettings();
});

/// Classes of the active year in menu order: (division id, "11th Science A").
List<(String, String)> orderedDivisions(AcademicSnapshot academic) => [
      for (final p in academic.programs)
        for (final d in academic.divisionsOf(p.id)) (d.id, '${p.name} ${d.name}'.trim()),
    ];

String messageKindLabel(AppLocalizations l10n, MessageKind kind) => switch (kind) {
      MessageKind.absent => l10n.msgKindAbsent,
      MessageKind.streak => l10n.msgKindStreak,
      MessageKind.summary => l10n.msgKindSummary,
    };

String messageChannelLabel(AppLocalizations l10n, String channel) =>
    channel == 'copy' ? l10n.msgChannelCopy : l10n.msgChannelWhatsApp;

/// Hands the text to WhatsApp: to one number, or (without a number) to a
/// chat the user picks. On Windows the WhatsApp app is tried first, then
/// WhatsApp Web. Returns false when nothing could be opened.
Future<bool> openWhatsApp({String? mobile, required String text}) async {
  final links = <Uri>[
    if (Platform.isWindows) mobile == null ? WhatsAppLink.desktopPickChat(text) : WhatsAppLink.desktopChat(mobile, text),
    mobile == null ? WhatsAppLink.pickChat(text) : WhatsAppLink.chat(mobile, text),
  ];
  for (final uri in links) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
    } catch (_) {
      // Not available this way; try the next one.
    }
  }
  return false;
}

Future<void> copyText(String text) => Clipboard.setData(ClipboardData(text: text));

/// The day summary as plain text for a staff WhatsApp group.
String daySummaryText(AppLocalizations l10n, DaySummary s, {required String institution}) {
  final lines = <String>[
    l10n.msgSummaryHeading(DateFormat('EEEE, d MMM y').format(s.date)),
    if (institution.trim().isNotEmpty) institution.trim(),
    '',
  ];
  if (!s.anyMarked) {
    lines.add(l10n.msgSummaryNone);
  }
  for (final d in s.divisions) {
    if (!d.marked) {
      lines.add(l10n.msgSummaryNotMarked(d.label));
      continue;
    }
    lines.add(l10n.msgSummaryClassLine(d.label, d.present, d.absent));
    if (d.absentees.isNotEmpty) {
      final names = [
        for (final (roll, name, code) in d.absentees)
          '${roll == null ? '' : '$roll. '}$name${code == 'A' ? '' : ' ($code)'}',
      ];
      lines.add('   ${names.join(', ')}');
    }
  }
  final counted = s.present + s.absent;
  if (counted > 0) {
    lines
      ..add('')
      ..add(l10n.msgSummaryTotal(s.present, s.absent, (s.present * 100 / counted).toStringAsFixed(1)));
  }
  return lines.join('\n').trim();
}

/// Message history as a report (Excel / PDF), exactly as listed on screen.
ReportDataset messageHistoryDataset(
  AppLocalizations l10n,
  List<MessageRecord> items, {
  DateTime? from,
  DateTime? to,
}) {
  final dates = DateFormat('dd/MM/yyyy');
  final times = DateFormat('dd/MM/yyyy h:mm a');
  String range() {
    if (from == null && to == null) return '';
    return '${from == null ? '…' : dates.format(from)} – ${to == null ? '…' : dates.format(to)}';
  }

  return ReportDataset(
    title: l10n.msgHistoryReport,
    subtitle: [range()],
    fileName: 'parent-messages',
    landscape: true,
    fontSize: 8.5,
    zebra: true,
    columns: [
      ReportColumn(l10n.reportSr, width: 26, align: ReportAlign.center, type: ReportColumnType.number),
      ReportColumn(l10n.msgColDate, width: 58, type: ReportColumnType.date),
      ReportColumn(l10n.msgColSentAt, width: 92),
      ReportColumn(l10n.msgColKind, width: 82),
      ReportColumn(l10n.msgColStudents, flex: 2),
      ReportColumn(l10n.fieldClass, width: 82),
      ReportColumn(l10n.msgColTo, flex: 1.4),
      ReportColumn(l10n.fieldMobile, width: 66),
      ReportColumn(l10n.msgColVia, width: 52),
      ReportColumn(l10n.msgColMessage, flex: 4),
    ],
    rows: [
      for (var i = 0; i < items.length; i++)
        ReportRow([
          '${i + 1}',
          dates.format(items[i].forDate),
          times.format(items[i].sentAt.toLocal()),
          messageKindLabel(l10n, items[i].kind),
          items[i].studentNames.join(', '),
          items[i].classNames.join(' / '),
          items[i].recipientName ?? '',
          items[i].mobile ?? '',
          messageChannelLabel(l10n, items[i].channel),
          items[i].body.replaceAll('\n', ' '),
        ]),
    ],
    notes: [l10n.msgHistoryNote],
  );
}
