import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/organization/organization_providers.dart';
import '../../../platform/reporting/report_output.dart';
import '../../reports/application/reports_providers.dart';
import '../../students/application/students_providers.dart';
import '../data/certificate_repository.dart';
import '../domain/certificate_models.dart';
import 'certificate_pdf.dart';

final certificateRepositoryProvider = Provider<CertificateRepository>(
  (ref) => CertificateRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(sessionProvider),
    ref.watch(studentRepositoryProvider),
  ),
);

/// Bumped after issuing, printing or cancelling.
final certificatesRevisionProvider = StateProvider<int>((ref) => 0);

String certificateTitle(AppLocalizations l10n, CertificateKind k) => switch (k) {
      CertificateKind.bonafide => l10n.certBonafide,
      CertificateKind.leaving => l10n.certLeaving,
      CertificateKind.nirgam => l10n.certNirgam,
      CertificateKind.noDues => l10n.certNoDues,
      CertificateKind.noc => l10n.certNoc,
      CertificateKind.character => l10n.certCharacter,
      CertificateKind.casteVerification => l10n.certCasteVerification,
    };

/// "this junior college", "this school"... from the institution type.
String institutionWord(WidgetRef ref) {
  final type = ref.read(activeOrganizationProvider).institutionType.trim().toLowerCase();
  return type.isEmpty || type == 'other' ? 'institution' : type;
}

Future<Uint8List> certificatePdf(
  WidgetRef ref, {
  required CertificateKind kind,
  required Map<String, String> fields,
  required String serialLabel,
  required DateTime issuedOn,
  bool duplicate = false,
  bool officeCopy = true,
}) async {
  return CertificatePdf.build(
    kind: kind,
    f: fields,
    serialLabel: serialLabel,
    issuedOn: issuedOn,
    head: await reportLetterhead(ref),
    fonts: await ReportOutput.fonts(),
    institutionWord: institutionWord(ref),
    duplicate: duplicate,
    officeCopy: officeCopy,
  );
}
