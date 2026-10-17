import 'staff_models.dart';

/// The permission a page needs, beyond the one its section needs to show
/// in the menu. Checked by the router, so a page someone may not use
/// cannot be opened from a link or a back button either.
String? permissionForPath(String path) {
  final p = path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;
  bool under(String prefix) => p == prefix || p.startsWith('$prefix/');

  if (p == '/students/new' || RegExp(r'^/students/[^/]+/edit$').hasMatch(p)) return Permissions.studentsEdit;
  if (under('/students/import') || under('/students/import-report') || under('/students/import-photos')) {
    return Permissions.studentsImport;
  }
  if (under('/students/promotion')) return Permissions.studentsPromote;
  if (under('/fees/setup') || under('/fees/structure')) return Permissions.feesSetup;
  if (under('/certificates/new')) return Permissions.certificatesIssue;
  if (under('/results/setup')) return Permissions.resultsSetup;
  if (under('/settings/staff')) return Permissions.staffManage;
  if (under('/settings/backup')) return Permissions.backupManage;
  if (under('/settings/security')) return Permissions.ownerOnly;
  if (under('/settings/imports')) return Permissions.studentsImport;
  if (p.startsWith('/settings/')) return Permissions.settingsManage;
  return null;
}
