import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backup/backup_service.dart';
import '../core/security/pin_lock_store.dart';
import '../core/security/secret_store.dart';
import '../design_system/theme/app_theme.dart';
import '../l10n/gen/app_localizations.dart';
import '../platform/data/data_providers.dart';
import '../platform/modules/module_providers.dart';
import '../platform/modules/module_registry.dart';
import '../platform/staff/staff_repository.dart';
import '../platform/workspace/institution_draft.dart';
import '../platform/workspace/workspace_actions.dart';
import '../platform/workspace/workspace_registry.dart';
import 'app.dart';
import 'lock/lock_controller.dart';
import 'lock/lock_screens.dart';
import 'startup/app_bootstrap.dart';
import 'startup/startup_state.dart';

/// Holds the open institution and the app lock. Switching institutions opens
/// the new database first, then rebuilds the whole app on it and closes the
/// old one, so screens can never mix two institutions' data.
class WorkspaceHost extends StatefulWidget {
  const WorkspaceHost({super.key, required this.initial, required this.registry});

  final StartupState initial;
  final ModuleRegistry registry;

  @override
  State<WorkspaceHost> createState() => _WorkspaceHostState();
}

class _WorkspaceHostState extends State<WorkspaceHost> implements WorkspaceActions {
  late StartupState _current = widget.initial;
  bool _busy = false;
  final LockController _lock = LockController(PinLockStore(const DeviceSecretStore()));
  bool _lockReady = false;

  @override
  void initState() {
    super.initState();
    _lock.addListener(_onLockChanged);
    AppBootstrap.listWorkspaces().then((all) async {
      await _lock.init(pinRequired: all.any((w) => !w.isDemo));
      if (mounted) setState(() => _lockReady = true);
    });
    _dailyBackup();
  }

  @override
  void dispose() {
    _lock.removeListener(_onLockChanged);
    _lock.dispose();
    super.dispose();
  }

  void _onLockChanged() {
    if (mounted) setState(() {});
  }

  /// Runs in the background; a failure here never disturbs the user.
  void _dailyBackup() {
    AppBootstrap.runDailyBackup(_current).catchError((Object _) {});
  }

  Future<void> _replaceWith(Future<StartupState> Function() open) async {
    setState(() => _busy = true);
    try {
      final next = await open();
      final previous = _current;
      setState(() {
        _current = next;
        _busy = false;
      });
      if (!identical(previous.database, next.database)) await previous.database.close().catchError((Object _) {});
      // Staff belong to one institution: the next one starts with its administrator.
      if (previous.session.organizationId != next.session.organizationId) _lock.resetUser();
      if (!next.isDemo) _lock.requirePin();
      _dailyBackup();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      rethrow;
    }
  }

  @override
  Future<List<WorkspaceInfo>> listWorkspaces() => AppBootstrap.listWorkspaces();

  @override
  Future<void> switchTo(String workspaceId) {
    if (workspaceId == _current.session.organizationId) return Future.value();
    return _replaceWith(() => AppBootstrap.open(widget.registry, workspaceId: workspaceId));
  }

  @override
  Future<void> createInstitution(InstitutionDraft draft) =>
      _replaceWith(() => AppBootstrap.createInstitution(widget.registry, draft));

  @override
  Future<void> renameCurrent(String name) => AppBootstrap.renameWorkspace(_current.session.organizationId, name);

  @override
  Future<void> restore(BackupContents contents) async {
    final currentId = _current.session.organizationId;
    final replacingOpen = contents.manifest.organizationId == currentId;
    if (replacingOpen) {
      await AppBootstrap.runBeforeBackup(_current, 'restore').catchError((Object _) {});
    }
    var closed = false;
    try {
      await _replaceWith(() => AppBootstrap.restore(
            widget.registry,
            contents,
            beforeSwap: (id) async {
              if (id == currentId) {
                await _current.database.close();
                closed = true;
              }
            },
          ));
    } catch (_) {
      // If the open database was closed for the swap, open it again.
      if (closed) {
        final reopened = await AppBootstrap.open(widget.registry, workspaceId: currentId);
        if (mounted) setState(() => _current = reopened);
      }
      rethrow;
    }
  }

  Widget _overlay(Widget child) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildSdTheme(brand: _current.organization.brandColor, brightness: Brightness.light),
      darkTheme: buildSdTheme(brand: _current.organization.brandColor, brightness: Brightness.dark),
      themeMode: _current.themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showSetup = _lockReady && _lock.needsSetup;
    final showLock = !_lockReady || (_lock.locked && !_lock.needsSetup);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          ProviderScope(
            key: ValueKey(_current.session.organizationId),
            overrides: [
              startupStateProvider.overrideWithValue(_current),
              moduleRegistryProvider.overrideWithValue(widget.registry),
              workspaceActionsProvider.overrideWithValue(this),
              lockControllerProvider.overrideWithValue(_lock),
              currentUserNotifierProvider.overrideWithValue(_lock.user),
            ],
            child: const ShikshaDeskApp(),
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (showSetup) Positioned.fill(child: _overlay(PinSetupScreen(controller: _lock))),
          if (showLock && _lockReady)
            Positioned.fill(
              child: _overlay(LockScreen(
                key: ValueKey('lock-${_current.session.organizationId}'),
                controller: _lock,
                staff: StaffRepository(_current.database, _current.session),
              )),
            ),
          if (!_lockReady) const Positioned.fill(child: ColoredBox(color: Color(0xFFF6F7F9))),
        ],
      ),
    );
  }
}
