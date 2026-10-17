import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/database/org_scoped_repository.dart';
import '../../core/ids/uuid7.dart';
import '../../core/security/pin_hasher.dart';
import '../data/app_settings_repository.dart';
import 'staff_models.dart';

/// Thrown when a staff change is not allowed; screens show a message.
enum StaffIssue { emptyName, badPin, unknownRole, notFound }

class StaffException implements Exception {
  const StaffException(this.issue);

  final StaffIssue issue;

  @override
  String toString() => 'StaffException(${issue.name})';
}

/// Staff members, their PINs and roles. Roles are kept in app settings.
class StaffRepository extends OrgScopedRepository {
  StaffRepository(super.db, super.session, {PinHasher? hasher}) : _hasher = hasher ?? PinHasher();

  final PinHasher _hasher;
  late final AppSettingsRepository _settings = AppSettingsRepository(db, session);

  static const _table = 'staff_members';

  // ================================================================= roles

  Future<List<StaffRole>> roles() async => StaffRoles.decode(await _settings.getValue(StaffRoles.settingKey));

  Future<void> saveRoles(List<StaffRole> roles) => _settings.setValue(StaffRoles.settingKey, StaffRoles.encode(roles));

  // ================================================================= staff

  static List<String> _divisions(String raw) {
    try {
      return [for (final d in jsonDecode(raw) as List<dynamic>) '$d'];
    } catch (_) {
      return const [];
    }
  }

  StaffMember _toModel(StaffMemberRow r) => StaffMember(
        id: r.id,
        name: r.name,
        mobile: r.mobile,
        roleKey: r.roleKey,
        active: r.active,
        hasPin: r.pinHash != null,
        pinLength: r.pinLength,
        divisionIds: _divisions(r.divisionsJson),
      );

  /// Everyone, active first, then by name.
  Future<List<StaffMember>> list() async {
    final rows = await (db.select(db.staffMembers)
          ..where((t) => t.organizationId.equals(orgId) & t.deletedAt.isNull()))
        .get();
    final out = rows.map(_toModel).toList()
      ..sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return out;
  }

  /// Adds or updates a staff member. A new member needs a PIN; for an
  /// existing one [pin] is optional (null keeps the old PIN). Returns the id.
  Future<String> save(StaffMember m, {String? pin}) async {
    final name = m.name.trim();
    if (name.isEmpty) throw const StaffException(StaffIssue.emptyName);
    if ((m.id == null || pin != null) && !PinHasher.isValidPin(pin ?? '')) throw const StaffException(StaffIssue.badPin);
    if (!(await roles()).any((r) => r.key == m.roleKey)) throw const StaffException(StaffIssue.unknownRole);
    final hash = pin == null ? null : await _hasher.hash(pin);
    final mobile = (m.mobile ?? '').trim().isEmpty ? null : m.mobile!.trim();
    return db.transaction(() async {
      final ts = now();
      final after = <String, Object?>{
        'name': name,
        'role': m.roleKey,
        'mobile': mobile,
        'active': m.active,
        'classes': m.divisionIds.length,
        if (pin != null) 'pin': 'changed',
      };
      if (m.id == null) {
        final id = Uuid7.generate(ts);
        await db.into(db.staffMembers).insert(StaffMembersCompanion.insert(
              id: id,
              organizationId: orgId,
              createdAt: ts,
              updatedAt: ts,
              createdBy: Value(session.userId),
              updatedBy: Value(session.userId),
              deviceId: session.deviceId,
              name: name,
              mobile: Value(mobile),
              roleKey: m.roleKey,
              pinHash: Value(hash),
              pinLength: Value(pin?.length ?? 4),
              active: Value(m.active),
              divisionsJson: Value(jsonEncode(m.divisionIds)),
            ));
        await changes.record(table: _table, rowId: id, operation: 'insert', after: after);
        return id;
      }
      final existing = await _row(m.id!);
      if (existing == null) throw const StaffException(StaffIssue.notFound);
      await (db.update(db.staffMembers)..where((t) => t.id.equals(existing.id))).write(StaffMembersCompanion(
        name: Value(name),
        mobile: Value(mobile),
        roleKey: Value(m.roleKey),
        active: Value(m.active),
        divisionsJson: Value(jsonEncode(m.divisionIds)),
        pinHash: hash == null ? const Value.absent() : Value(hash),
        pinLength: pin == null ? const Value.absent() : Value(pin.length),
        updatedAt: Value(ts),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(existing.rowVersion + 1),
      ));
      await changes.record(
        table: _table,
        rowId: existing.id,
        operation: 'update',
        before: {'name': existing.name, 'role': existing.roleKey, 'mobile': existing.mobile, 'active': existing.active},
        after: after,
      );
      return existing.id;
    });
  }

  /// A staff member changes their own PIN, or the admin resets it.
  Future<void> setPin(String id, String pin) async {
    final m = (await list()).where((s) => s.id == id).firstOrNull;
    if (m == null) throw const StaffException(StaffIssue.notFound);
    await save(m, pin: pin);
  }

  Future<StaffMemberRow?> _row(String id) => (db.select(db.staffMembers)
        ..where((t) => t.organizationId.equals(orgId) & t.id.equals(id) & t.deletedAt.isNull()))
      .getSingleOrNull();

  /// Removes a staff member (to the recycle bin; their past work keeps their name).
  Future<void> remove(String id) {
    return db.transaction(() async {
      final ts = now();
      await (db.update(db.staffMembers)..where((t) => t.id.equals(id) & t.organizationId.equals(orgId)))
          .write(StaffMembersCompanion(deletedAt: Value(ts), updatedAt: Value(ts), updatedBy: Value(session.userId)));
      await changes.record(table: _table, rowId: id, operation: 'delete', after: {'deleted': true});
    });
  }

  // ================================================================= login

  /// Active staff with a PIN, for the "Who is using?" screen.
  Future<List<StaffLogin>> logins() async {
    final roleLabels = {for (final r in await roles()) r.key: r.label};
    return [
      for (final m in await list())
        if (m.active && m.hasPin && m.id != null)
          (id: m.id!, name: m.name, roleLabel: roleLabels[m.roleKey] ?? m.roleKey, pinLength: m.pinLength),
    ];
  }

  /// True when [pin] is this active staff member's PIN.
  Future<bool> verifyPin(String id, String pin) async {
    final r = await _row(id);
    if (r == null || !r.active) return false;
    return _hasher.matches(pin, r.pinHash);
  }

  /// What a staff member may do, from their role. Null when they cannot log in.
  Future<CurrentUser?> accessFor(String id) async {
    final r = await _row(id);
    if (r == null || !r.active) return null;
    final role = (await roles()).where((x) => x.key == r.roleKey).firstOrNull;
    return CurrentUser(
      id: r.id,
      name: r.name,
      roleKey: r.roleKey,
      permissions: role?.permissions ?? const {},
      divisionIds: _divisions(r.divisionsJson),
    );
  }

  /// Display names of staff (and the admin) by user id, for "Issued by" and history.
  Future<Map<String, String>> names() async {
    final rows = await (db.select(db.staffMembers)..where((t) => t.organizationId.equals(orgId))).get();
    return {for (final r in rows) r.id: r.name};
  }
}
