import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_service.dart';
import 'institution_draft.dart';
import 'workspace_registry.dart';

/// Switching and creating institutions. Implemented by the app's
/// WorkspaceHost, which reopens everything for the chosen institution.
abstract class WorkspaceActions {
  Future<List<WorkspaceInfo>> listWorkspaces();
  Future<void> switchTo(String workspaceId);
  Future<void> createInstitution(InstitutionDraft draft);
  Future<void> renameCurrent(String name);

  /// Restores an institution from an opened backup and switches to it.
  Future<void> restore(BackupContents contents);
}

final workspaceActionsProvider = Provider<WorkspaceActions>(
  (ref) => throw UnimplementedError('workspaceActionsProvider must be overridden by WorkspaceHost'),
);
