import 'package:drift/drift.dart';
import 'package:flutter/painting.dart';

import '../../core/database/app_database.dart';
import '../../core/database/org_scoped_repository.dart';
import '../organization/organization_profile.dart';

/// The institution record for the open workspace.
class OrganizationRepository extends OrgScopedRepository {
  OrganizationRepository(super.db, super.session);

  static const _table = 'organizations';

  Future<OrganizationProfile?> loadActive() async {
    final row = await (db.select(db.organizations)
          ..where((t) => t.id.equals(orgId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    return OrganizationProfile(
      id: row.id,
      name: row.name,
      shortName: row.shortName,
      institutionType: row.institutionType,
      city: row.city,
      activeAcademicYear: row.activeAcademicYear,
      brandColor: Color(row.brandColor),
      address: row.address,
      state: row.state,
      phone: row.phone,
      email: row.email,
      website: row.website,
      board: row.board,
      medium: row.medium,
      udiseCode: row.udiseCode,
      logoFileName: row.logoFileName,
      programLabel: row.programLabel,
      divisionLabel: row.divisionLabel,
    );
  }

  /// Creates the record for this workspace. The id is always the session's
  /// organization id, so the institution and its workspace share one id.
  Future<void> create(OrganizationProfile profile) {
    return db.transaction(() async {
      final ts = now();
      await db.into(db.organizations).insert(OrganizationsCompanion.insert(
            id: orgId,
            organizationId: orgId,
            createdAt: ts,
            updatedAt: ts,
            createdBy: Value(session.userId),
            updatedBy: Value(session.userId),
            deviceId: session.deviceId,
            name: profile.name,
            shortName: profile.shortName,
            institutionType: profile.institutionType,
            city: Value(profile.city),
            brandColor: profile.brandColor.toARGB32(),
            activeAcademicYear: profile.activeAcademicYear,
            address: Value(profile.address),
            state: Value(profile.state),
            phone: Value(profile.phone),
            email: Value(profile.email),
            website: Value(profile.website),
            board: Value(profile.board),
            medium: Value(profile.medium),
            udiseCode: Value(profile.udiseCode),
            logoFileName: Value(profile.logoFileName),
            programLabel: Value(profile.programLabel),
            divisionLabel: Value(profile.divisionLabel),
          ));
      await changes.record(table: _table, rowId: orgId, operation: 'insert', after: profile.toAuditMap());
    });
  }

  /// Saves edited details. Empty text is stored as "not set".
  Future<void> update(OrganizationProfile profile) {
    return db.transaction(() async {
      final before = await loadActive();
      if (before == null) throw StateError('Institution record missing');
      final existing = await (db.select(db.organizations)..where((t) => t.id.equals(orgId))).getSingle();
      String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
      final after = OrganizationProfile(
        id: orgId,
        name: profile.name.trim(),
        shortName: profile.shortName.trim(),
        institutionType: profile.institutionType,
        city: profile.city.trim(),
        activeAcademicYear: profile.activeAcademicYear,
        brandColor: profile.brandColor,
        address: clean(profile.address),
        state: clean(profile.state),
        phone: clean(profile.phone),
        email: clean(profile.email),
        website: clean(profile.website),
        board: clean(profile.board),
        medium: clean(profile.medium),
        udiseCode: clean(profile.udiseCode),
        logoFileName: clean(profile.logoFileName),
        programLabel: clean(profile.programLabel),
        divisionLabel: clean(profile.divisionLabel),
      );
      if (after.name.isEmpty || after.shortName.isEmpty) {
        throw ArgumentError('Institution name and short name are required');
      }
      final ts = now();
      await (db.update(db.organizations)..where((t) => t.id.equals(orgId))).write(OrganizationsCompanion(
        name: Value(after.name),
        shortName: Value(after.shortName),
        institutionType: Value(after.institutionType),
        city: Value(after.city),
        activeAcademicYear: Value(after.activeAcademicYear),
        brandColor: Value(after.brandColor.toARGB32()),
        address: Value(after.address),
        state: Value(after.state),
        phone: Value(after.phone),
        email: Value(after.email),
        website: Value(after.website),
        board: Value(after.board),
        medium: Value(after.medium),
        udiseCode: Value(after.udiseCode),
        logoFileName: Value(after.logoFileName),
        programLabel: Value(after.programLabel),
        divisionLabel: Value(after.divisionLabel),
        updatedAt: Value(ts),
        updatedBy: Value(session.userId),
        deviceId: Value(session.deviceId),
        rowVersion: Value(existing.rowVersion + 1),
      ));
      await changes.record(
        table: _table,
        rowId: orgId,
        operation: 'update',
        before: before.toAuditMap(),
        after: after.toAuditMap(),
      );
    });
  }
}
