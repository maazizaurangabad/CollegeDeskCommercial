import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The person who holds the app PIN. Not a row in the staff table.
const localAdminUserId = 'local-admin';

/// Every permission a role can have. Screens and routes ask for these by key.
abstract final class Permissions {
  static const studentsView = 'students.view';
  static const studentsEdit = 'students.edit';
  static const studentsDelete = 'students.delete';
  static const studentsSensitive = 'students.view_sensitive';
  static const studentsImport = 'students.import';
  static const studentsPromote = 'students.promote';
  static const attendanceMark = 'attendance.mark';
  static const attendancePast = 'attendance.edit_past';
  static const messagesSend = 'messages.send';
  static const feesCollect = 'fees.collect';
  static const feesCancel = 'fees.cancel';
  static const feesSetup = 'fees.setup';
  static const certificatesIssue = 'certificates.issue';
  static const certificatesCancel = 'certificates.cancel';
  static const resultsMarks = 'results.manage';
  static const resultsSetup = 'results.setup';
  static const reportsView = 'reports.view';
  static const settingsManage = 'settings.manage';
  static const staffManage = 'staff.manage';
  static const backupManage = 'backup.manage';

  /// Only the administrator (app PIN): app lock, fingerprint, institutions.
  static const ownerOnly = 'owner.only';

  /// In the order the role editor shows them, by section.
  static const groups = <(String, List<String>)>[
    ('students', [studentsView, studentsEdit, studentsDelete, studentsSensitive, studentsImport, studentsPromote]),
    ('attendance', [attendanceMark, attendancePast]),
    ('messages', [messagesSend]),
    ('fees', [feesCollect, feesCancel, feesSetup]),
    ('certificates', [certificatesIssue, certificatesCancel]),
    ('results', [resultsMarks, resultsSetup]),
    ('reports', [reportsView]),
    ('settings', [settingsManage, staffManage, backupManage]),
  ];

  static final all = {for (final g in groups) ...g.$2};
}

/// A set of permissions given a name (Principal, Clerk...).
@immutable
class StaffRole {
  const StaffRole({required this.key, required this.label, required this.permissions, this.builtIn = false});

  final String key;
  final String label;
  final Set<String> permissions;

  /// One of the standard roles; it can be changed but not deleted.
  final bool builtIn;

  StaffRole copyWith({String? label, Set<String>? permissions}) =>
      StaffRole(key: key, label: label ?? this.label, permissions: permissions ?? this.permissions, builtIn: builtIn);

  Map<String, Object?> toJson() => {
        'key': key,
        'label': label,
        'permissions': [for (final p in Permissions.all) if (permissions.contains(p)) p],
        'builtIn': builtIn,
      };

  static StaffRole fromJson(Map<String, dynamic> j) => StaffRole(
        key: '${j['key']}',
        label: '${j['label']}',
        permissions: {for (final p in (j['permissions'] as List<dynamic>? ?? const [])) '$p'},
        builtIn: j['builtIn'] == true,
      );
}

abstract final class StaffRoles {
  static const settingKey = 'staff.roles';

  static const adminKey = 'admin';
  static const teacherKey = 'teacher';

  static final defaults = <StaffRole>[
    StaffRole(key: adminKey, label: 'Admin', permissions: Permissions.all, builtIn: true),
    StaffRole(
      key: 'principal',
      label: 'Principal',
      permissions: {...Permissions.all}..removeAll(const [Permissions.staffManage, Permissions.backupManage]),
      builtIn: true,
    ),
    const StaffRole(
      key: 'clerk',
      label: 'Clerk / Office',
      permissions: {
        Permissions.studentsView,
        Permissions.studentsEdit,
        Permissions.studentsSensitive,
        Permissions.studentsImport,
        Permissions.attendanceMark,
        Permissions.messagesSend,
        Permissions.feesCollect,
        Permissions.certificatesIssue,
        Permissions.reportsView,
      },
      builtIn: true,
    ),
    const StaffRole(
      key: 'accountant',
      label: 'Accountant',
      permissions: {Permissions.feesCollect, Permissions.feesCancel, Permissions.feesSetup, Permissions.reportsView},
      builtIn: true,
    ),
    const StaffRole(
      key: teacherKey,
      label: 'Teacher',
      permissions: {Permissions.studentsView, Permissions.attendanceMark, Permissions.resultsMarks},
      builtIn: true,
    ),
  ];

  /// Saved roles, or the standard ones when nothing is saved yet. The
  /// standard roles are always present (added back if missing).
  static List<StaffRole> decode(String? raw) {
    if (raw == null) return defaults;
    try {
      final saved = [for (final j in jsonDecode(raw) as List<dynamic>) StaffRole.fromJson(j as Map<String, dynamic>)];
      final keys = saved.map((r) => r.key).toSet();
      return [
        for (final d in defaults)
          if (!keys.contains(d.key)) d,
        ...saved,
      ]..sort((a, b) => _rank(a).compareTo(_rank(b)));
    } catch (_) {
      return defaults;
    }
  }

  static int _rank(StaffRole r) {
    final i = defaults.indexWhere((d) => d.key == r.key);
    return i < 0 ? 100 : i;
  }

  static String encode(List<StaffRole> roles) => jsonEncode([for (final r in roles) r.toJson()]);

  /// A key for a new role from its name ("Lab assistant" -> lab_assistant).
  static String keyFor(String label, Iterable<String> taken) {
    var base = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    if (base.isEmpty) base = 'role';
    var key = base, n = 2;
    while (taken.contains(key)) {
      key = '${base}_${n++}';
    }
    return key;
  }
}

/// A staff member as the Staff screen shows them.
@immutable
class StaffMember {
  const StaffMember({
    this.id,
    required this.name,
    required this.roleKey,
    this.mobile,
    this.active = true,
    this.hasPin = false,
    this.pinLength = 4,
    this.divisionIds = const [],
  });

  /// Null until saved.
  final String? id;
  final String name;
  final String? mobile;
  final String roleKey;
  final bool active;
  final bool hasPin;
  final int pinLength;

  /// Classes (divisions) a teacher works with.
  final List<String> divisionIds;

  StaffMember copyWith({String? name, String? mobile, String? roleKey, bool? active, List<String>? divisionIds}) =>
      StaffMember(
        id: id,
        name: name ?? this.name,
        mobile: mobile ?? this.mobile,
        roleKey: roleKey ?? this.roleKey,
        active: active ?? this.active,
        hasPin: hasPin,
        pinLength: pinLength,
        divisionIds: divisionIds ?? this.divisionIds,
      );
}

/// One name on the "Who is using?" screen.
typedef StaffLogin = ({String id, String name, String roleLabel, int pinLength});

/// The person using the app right now, and what they may do.
@immutable
class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.name,
    required this.roleKey,
    required this.permissions,
    this.isOwner = false,
    this.divisionIds = const [],
  });

  /// The administrator who holds the app PIN: allowed everything.
  static const owner = CurrentUser(
    id: localAdminUserId,
    name: 'Admin',
    roleKey: StaffRoles.adminKey,
    permissions: {},
    isOwner: true,
  );

  final String id;
  final String name;
  final String roleKey;
  final Set<String> permissions;
  final bool isOwner;
  final List<String> divisionIds;

  bool can(String permission) {
    if (isOwner) return true;
    if (permission == Permissions.ownerOnly) return false;
    return permissions.contains(permission);
  }
}
