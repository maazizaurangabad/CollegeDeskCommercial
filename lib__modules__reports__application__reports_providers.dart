import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/organization/institution_seal.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../../platform/reporting/pdf_report_renderer.dart';
import '../../attendance/application/attendance_providers.dart';
import '../../certificates/application/certificates_providers.dart';
import '../../students/application/students_providers.dart';
import '../../students/presentation/student_labels.dart';
import 'report_builders.dart';

/// Report builders wired to this institution's data.
Future<ReportBuilders> reportBuilders(WidgetRef ref, AppLocalizations l10n) async {
  return ReportBuilders(
    l10n: l10n,
    academic: ref.read(academicControllerProvider),
    attendance: ref.read(attendanceRepositoryProvider),
    students: ref.read(studentRepositoryProvider),
    divisionLabels: await ref.read(academicRepositoryProvider).divisionLabels(),
    certificates: ref.read(certificateRepositoryProvider),
    certificateTitle: (k) => certificateTitle(l10n, k),
    photoBytes: (fileName) async {
      final file = studentPhoto(ref.read(startupStateProvider).mediaDir, fileName);
      return file == null ? null : await file.readAsBytes();
    },
  );
}

/// The institution's letterhead from Settings: name, address, contacts, UDISE, logo.
Future<ReportLetterhead> reportLetterhead(WidgetRef ref) async {
  final org = ref.read(activeOrganizationProvider);
  final logo = InstitutionSeal.logoIn(ref.read(startupStateProvider).mediaDir, org.logoFileName);
  final place = [org.address, org.city, org.state].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
  final contact = [
    if ((org.phone ?? '').isNotEmpty) 'Phone: ${org.phone}',
    if ((org.email ?? '').isNotEmpty) org.email!,
    if ((org.udiseCode ?? '').isNotEmpty) 'UDISE: ${org.udiseCode}',
  ].join('   ');
  return ReportLetterhead(
    name: org.name,
    lines: [place, contact, if ((org.board ?? '').isNotEmpty) org.board!],
    logo: logo == null ? null : await logo.readAsBytes(),
    brandColor: org.brandColor.toARGB32(),
  );
}
