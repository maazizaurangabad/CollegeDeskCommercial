import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../app/startup/app_bootstrap.dart';
import '../../../core/backup/backup_codec.dart';
import '../../../core/backup/backup_password_store.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/files/save_file.dart';
import '../../../core/security/secret_store.dart';
import '../../../design_system/components/components.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../platform/data/data_providers.dart';
import '../../../platform/workspace/workspace_actions.dart';
import 'settings_page_header.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _passwords = BackupPasswordStore(const DeviceSecretStore());
  bool _busy = false;
  String? _busyText;
  int _revision = 0;

  Future<void> _run(String text, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _busyText = text;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _revision++;
        });
      }
    }
  }

  Future<void> _setPassword() async {
    final l10n = AppLocalizations.of(context);
    final password = await showDialog<String>(context: context, builder: (_) => const _PasswordDialog());
    if (password == null) return;
    final hadOne = await _passwords.read() != null;
    await _passwords.write(password);
    if (!mounted) return;
    SdToast.show(context, hadOne ? '${l10n.backupPasswordSaved}. ${l10n.backupPasswordChangedNote}' : l10n.backupPasswordSaved);
    setState(() => _revision++);
    AppBootstrap.runDailyBackup(ref.read(startupStateProvider)).catchError((Object _) {});
  }

  Future<void> _backupNow() async {
    final l10n = AppLocalizations.of(context);
    if (await _passwords.read() == null) {
      if (mounted) SdToast.show(context, l10n.backupNeedsPassword);
      return;
    }
    final state = ref.read(startupStateProvider);
    await _run(l10n.backupMaking, () async {
      final bytes = await AppBootstrap.backupBytes(state);
      if (bytes == null) return;
      final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final name = '${state.organization.shortName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}-$day.${BackupService.fileExtension}';
      final saved = await saveBytesWithDialog(fileName: name, bytes: bytes, title: l10n.backupNow);
      if (!saved) return;
      await ref.read(appSettingsRepositoryProvider).setValue(AppBootstrap.lastSavedKey, DateTime.now().toUtc().toIso8601String());
      if (mounted) SdToast.show(context, l10n.backupSaved);
    });
  }

  Future<void> _restoreFromFile() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return;
    await _restoreBytes(await File(path).readAsBytes());
  }

  Future<void> _restoreBytes(Uint8List bytes) async {
    final l10n = AppLocalizations.of(context);
    if (!BackupCodec.isBackup(bytes)) {
      SdToast.show(context, l10n.restoreNotBackup);
      return;
    }
    // Try the saved password first; ask only if it does not open.
    BackupContents? contents;
    final saved = await _passwords.read();
    String? error;
    for (var attempt = 0; attempt < 4 && contents == null; attempt++) {
      String? password = attempt == 0 ? saved : null;
      if (password == null) {
        if (!mounted) return;
        password = await SdDialog.prompt(
          context,
          title: l10n.restoreEnterPassword,
          label: error ?? l10n.restoreEnterPassword,
          confirmLabel: l10n.next,
          cancelLabel: l10n.cancel,
        );
        if (password == null) return;
      }
      try {
        setState(() {
          _busy = true;
          _busyText = l10n.restoreReading;
        });
        contents = await AppBootstrap.readBackup(bytes, password);
      } on BackupPasswordException {
        error = l10n.restoreWrongPassword;
      } on BackupTooNewException {
        if (mounted) SdToast.show(context, l10n.restoreTooNew);
        return;
      } on Object {
        if (mounted) SdToast.show(context, l10n.restoreNotBackup);
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (contents == null || !mounted) return;

    final m = contents.manifest;
    final replacing = m.organizationId == ref.read(sessionProvider).organizationId ||
        (await ref.read(workspaceActionsProvider).listWorkspaces()).any((w) => w.id == m.organizationId);
    if (!mounted) return;
    final ok = await SdDialog.confirm(
      context,
      title: l10n.restoreConfirmTitle,
      message: '${l10n.restoreSummary(m.organizationName, DateFormat('d MMM y, h:mm a').format(m.createdAt.toLocal()), m.studentCount)}'
          '\n\n${replacing ? l10n.restoreReplaces : l10n.restoreAdds}',
      confirmLabel: l10n.restoreButton,
      cancelLabel: l10n.cancel,
      destructive: replacing,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(workspaceActionsProvider).restore(contents);
      messenger.showSnackBar(SnackBar(content: Text(l10n.restoreDone)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.restoreFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(startupStateProvider);
    final dates = DateFormat('d MMM y, h:mm a');

    return SdPage(
      children: [
        SettingsPageHeader(title: l10n.backupTitle),
        if (_busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: SdSpace.sm),
          Text(_busyText ?? '', style: theme.textTheme.bodySmall),
          const SizedBox(height: SdSpace.lg),
        ],
        FutureBuilder<String?>(
          key: ValueKey('pw$_revision'),
          future: _passwords.read(),
          builder: (context, snapshot) {
            final isSet = snapshot.data != null;
            return SdSection(
              title: l10n.backupPassword,
              child: SdCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isSet ? l10n.backupPasswordIsSet : l10n.backupPasswordMissing),
                    const SizedBox(height: SdSpace.md),
                    SdButton(
                      label: isSet ? l10n.backupPasswordChange : l10n.backupPasswordSet,
                      variant: isSet ? SdButtonVariant.secondary : SdButtonVariant.primary,
                      onPressed: _busy ? null : _setPassword,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: SdSpace.xl),
        SdSection(
          title: l10n.backupNow,
          child: SdCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.backupNowExplain),
                const SizedBox(height: SdSpace.sm),
                FutureBuilder<String?>(
                  key: ValueKey('last$_revision'),
                  future: ref.read(appSettingsRepositoryProvider).getValue(AppBootstrap.lastSavedKey),
                  builder: (context, snapshot) {
                    final last = snapshot.data == null ? null : DateTime.tryParse(snapshot.data!);
                    return Text(
                      l10n.backupLastSaved(last == null ? l10n.backupNever : dates.format(last.toLocal())),
                      style: theme.textTheme.bodySmall,
                    );
                  },
                ),
                const SizedBox(height: SdSpace.md),
                SdButton(label: l10n.backupNow, icon: Icons.backup_outlined, onPressed: _busy ? null : _backupNow),
              ],
            ),
          ),
        ),
        const SizedBox(height: SdSpace.xl),
        SdSection(
          title: l10n.restoreFromFile,
          child: SdCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.restoreExplain),
                const SizedBox(height: SdSpace.md),
                SdButton(
                  label: l10n.restoreFromFile,
                  icon: Icons.settings_backup_restore,
                  variant: SdButtonVariant.secondary,
                  onPressed: _busy ? null : _restoreFromFile,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SdSpace.xl),
        SdSection(
          title: l10n.autoBackupsTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.autoBackupsExplain, style: theme.textTheme.bodySmall),
              const SizedBox(height: SdSpace.md),
              FutureBuilder<List<File>>(
                key: ValueKey('auto$_revision'),
                future: AppBootstrap.listAutoBackups(state.session.organizationId),
                builder: (context, snapshot) {
                  final files = snapshot.data ?? const <File>[];
                  if (files.isEmpty) return SdCard(child: Text(l10n.autoBackupsEmpty));
                  return SdCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < files.length; i++) ...[
                          if (i > 0) const Divider(indent: SdSpace.lg),
                          ListTile(
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: Text(dates.format(files[i].lastModifiedSync())),
                            subtitle: Text(
                              '${p.basename(files[i].path)} · ${(files[i].lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB',
                            ),
                            trailing: PopupMenuButton<String>(
                              enabled: !_busy,
                              onSelected: (v) async {
                                final bytes = await files[i].readAsBytes();
                                if (!context.mounted) return;
                                if (v == 'save') {
                                  final ok = await saveBytesWithDialog(
                                    fileName: p.basename(files[i].path),
                                    bytes: bytes,
                                    title: l10n.saveCopy,
                                  );
                                  if (ok) {
                                    await ref.read(appSettingsRepositoryProvider).setValue(
                                          AppBootstrap.lastSavedKey,
                                          DateTime.now().toUtc().toIso8601String(),
                                        );
                                    if (mounted) setState(() => _revision++);
                                  }
                                } else {
                                  await _restoreBytes(bytes);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'save', child: Text(l10n.saveCopy)),
                                PopupMenuItem(value: 'restore', child: Text(l10n.restoreButton)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: SdSpace.xxl),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;
  bool _show = false;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.backupPassword),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.backupPasswordExplain, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: SdSpace.lg),
            TextField(
              controller: _a,
              obscureText: !_show,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.backupPassword,
                suffixIcon: IconButton(
                  icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
            const SizedBox(height: SdSpace.md),
            TextField(
              controller: _b,
              obscureText: !_show,
              decoration: InputDecoration(labelText: l10n.backupPasswordAgain, errorText: _error),
            ),
          ],
        ),
      ),
      actions: [
        SdButton(label: l10n.cancel, variant: SdButtonVariant.text, onPressed: () => Navigator.of(context).pop()),
        SdButton(
          label: l10n.save,
          onPressed: () {
            if (!BackupPasswordStore.isStrongEnough(_a.text)) {
              setState(() => _error = l10n.backupPasswordShort);
            } else if (_a.text != _b.text) {
              setState(() => _error = l10n.backupPasswordMismatch);
            } else {
              Navigator.of(context).pop(_a.text);
            }
          },
        ),
      ],
    );
  }
}
