import '../../design_system/tokens/colors.dart';
import '../organization/organization_profile.dart';

/// Fictional institution and figures for demo mode.
/// Never put real student or institution data in this file or anywhere in the code.
abstract final class DemoData {
  static const organization = OrganizationProfile(
    id: 'demo-org-0001',
    name: 'Greenfield Junior College',
    shortName: 'Greenfield College',
    institutionType: 'Junior college',
    city: 'Demo City',
    activeAcademicYear: '2026-27',
    brandColor: SdPalette.ink,
  );

  static final academicYear = (label: '2026-27', start: DateTime(2026, 6, 1), end: DateTime(2027, 4, 30));

  static const snapshot = DemoSnapshot(totalStudents: 486, present: 451, absent: 35);
}

class DemoSnapshot {
  const DemoSnapshot({required this.totalStudents, required this.present, required this.absent});

  final int totalStudents;
  final int present;
  final int absent;

  double get attendancePercent => totalStudents == 0 ? 0 : present * 100 / totalStudents;
}
