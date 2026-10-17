import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../design_system/components/components.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../platform/staff/staff_models.dart';
import '../../platform/staff/staff_repository.dart';
import 'lock_controller.dart';

/// Full-screen PIN entry with an on-screen number pad.
class PinPad extends StatelessWidget {
  const PinPad({super.key, required this.value, required this.onChanged, this.maxLength = 6, this.extra});

  final String value;
  final ValueChanged<String> onChanged;
  final int maxLength;

  /// Bottom-left key, e.g. the fingerprint button.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget key(String label) => SizedBox(
          width: 72,
          height: 64,
          child: TextButton(
            onPressed: value.length >= maxLength ? null : () => onChanged(value + label),
            child: Text(label, style: theme.textTheme.headlineSmall),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < maxLength; i++)
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < value.length ? theme.colorScheme.primary : Colors.transparent,
                  border: Border.all(color: theme.colorScheme.primary, width: 1.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: SdSpace.xl),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(mainAxisSize: MainAxisSize.min, children: [for (final k in row) key(k)]),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 72, height: 64, child: extra ?? const SizedBox()),
            key('0'),
            SizedBox(
              width: 72,
              height: 64,
              child: IconButton(
                icon: const Icon(Icons.backspace_outlined),
                onPressed: value.isEmpty ? null : () => onChanged(value.substring(0, value.length - 1)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shown over the whole app while it is locked. With staff set up it first
/// asks "Who is using?": the administrator (app PIN) or a staff member
/// (their own PIN). Without staff it is just the app PIN, as before.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.controller, this.staff});

  final LockController controller;

  /// Staff of the open institution; null shows the app PIN only.
  final StaffRepository? staff;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _error;
  bool _checking = false;
  bool _biometricAvailable = false;
  int _adminLength = 6;

  /// Staff who can log in; empty means only the administrator.
  List<StaffLogin> _staff = const [];
  bool _staffLoaded = false;

  /// Who is entering a PIN: null = not chosen yet, '' = administrator.
  String? _who;

  // Wrong staff PINs: after a few, wait before trying again.
  int _staffFailures = 0;
  DateTime? _staffBlockedUntil;
  static const _staffFreeAttempts = 5;
  static const _staffWait = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    widget.controller.store.pinLength().then((n) {
      if (mounted) setState(() => _adminLength = n);
    });
    _loadStaff();
    if (widget.controller.biometricEnabled) {
      LocalAuthentication().isDeviceSupported().then((ok) {
        if (!mounted) return;
        setState(() => _biometricAvailable = ok);
        if (ok) _biometric();
      }).catchError((Object _) {});
    }
  }

  Future<void> _loadStaff() async {
    var list = const <StaffLogin>[];
    try {
      list = await widget.staff?.logins() ?? const [];
    } catch (_) {
      // Staff could not be read: the app PIN still works.
    }
    if (!mounted) return;
    setState(() {
      _staff = list;
      _staffLoaded = true;
      if (list.isEmpty) _who = '';
    });
  }

  int get _length {
    final who = _who;
    if (who == null || who.isEmpty) return _adminLength;
    return _staff.where((s) => s.id == who).firstOrNull?.pinLength ?? 4;
  }

  Future<void> _biometric() async {
    final l10n = AppLocalizations.of(context);
    try {
      final ok = await LocalAuthentication().authenticate(localizedReason: l10n.lockBiometricReason);
      if (!ok) return;
      final id = await widget.controller.store.biometricUserId();
      if (id == null) {
        widget.controller.unlock();
        return;
      }
      final user = await widget.staff?.accessFor(id);
      if (user != null) {
        widget.controller.unlockAs(user);
      } else if (mounted) {
        setState(() => _error = l10n.lockBiometricNoUser);
      }
    } catch (_) {
      // Cancelled or not available: the PIN still works.
    }
  }

  Future<void> _changed(String value) async {
    setState(() {
      _pin = value;
      _error = null;
    });
    if (value.length < _length || _checking) return;
    final l10n = AppLocalizations.of(context);
    final who = _who ?? '';
    if (who.isNotEmpty) {
      final until = _staffBlockedUntil;
      if (until != null && until.isAfter(DateTime.now())) {
        setState(() {
          _pin = '';
          _error = l10n.lockBlocked(until.difference(DateTime.now()).inSeconds + 1);
        });
        return;
      }
    }
    setState(() => _checking = true);
    if (who.isEmpty) {
      final ok = await widget.controller.store.verifyPin(value);
      if (!mounted) return;
      if (ok) {
        widget.controller.unlock();
        return;
      }
      final blocked = await widget.controller.store.blockedUntil();
      if (!mounted) return;
      setState(() {
        _checking = false;
        _pin = '';
        _error = blocked == null ? l10n.lockWrongPin : l10n.lockBlocked(blocked.difference(DateTime.now()).inSeconds + 1);
      });
      return;
    }
    CurrentUser? user;
    try {
      final repo = widget.staff;
      if (repo != null && await repo.verifyPin(who, value)) user = await repo.accessFor(who);
    } catch (_) {
      user = null;
    }
    if (!mounted) return;
    if (user != null) {
      _staffFailures = 0;
      widget.controller.unlockAs(user);
      return;
    }
    _staffFailures++;
    if (_staffFailures >= _staffFreeAttempts) {
      _staffFailures = 0;
      _staffBlockedUntil = DateTime.now().add(_staffWait);
    }
    setState(() {
      _checking = false;
      _pin = '';
      _error = l10n.lockWrongPin;
    });
  }

  void _choose(String? who) => setState(() {
        _who = who;
        _pin = '';
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final fingerprint = _biometricAvailable
        ? IconButton(
            tooltip: l10n.lockUseBiometric,
            icon: const Icon(Icons.fingerprint, size: 32),
            onPressed: _biometric,
          )
        : null;

    Widget body;
    if (!_staffLoaded) {
      body = const Padding(padding: EdgeInsets.all(SdSpace.xl), child: CircularProgressIndicator());
    } else if (_who == null) {
      body = _WhoIsUsing(
        staff: _staff,
        error: _error,
        onChoose: _choose,
        fingerprint: fingerprint,
      );
    } else {
      final staffName = _staff.where((s) => s.id == _who).firstOrNull?.name;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: SdSpace.md),
          Text(
            _staff.isEmpty ? l10n.lockTitle : (staffName ?? l10n.staffAdminName),
            style: theme.textTheme.titleLarge,
          ),
          if (_staff.isNotEmpty) Text(l10n.lockEnterYourPin, style: theme.textTheme.bodySmall),
          const SizedBox(height: SdSpace.sm),
          SizedBox(
            height: 20,
            child: Text(_error ?? '', style: theme.textTheme.bodySmall?.copyWith(color: SdColors.of(context).absent)),
          ),
          const SizedBox(height: SdSpace.lg),
          PinPad(
            value: _pin,
            maxLength: _length,
            onChanged: _changed,
            extra: (_who ?? '').isEmpty ? fingerprint : null,
          ),
          const SizedBox(height: SdSpace.lg),
          if (_staff.isNotEmpty)
            TextButton.icon(
              onPressed: () => _choose(null),
              icon: const Icon(Icons.people_outline),
              label: Text(l10n.lockSomeoneElse),
            ),
          if ((_who ?? '').isEmpty)
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => RecoveryScreen(controller: widget.controller),
              )),
              child: Text(l10n.lockForgot),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SdSpace.xl),
              child: Text(l10n.lockStaffForgot, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            ),
        ],
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(child: SingleChildScrollView(child: body)),
      ),
    );
  }
}

/// "Who is using?": the administrator first, then each staff member.
class _WhoIsUsing extends StatelessWidget {
  const _WhoIsUsing({required this.staff, required this.onChoose, this.error, this.fingerprint});

  final List<StaffLogin> staff;
  final ValueChanged<String> onChoose;
  final String? error;
  final Widget? fingerprint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget person(String id, String name, String subtitle, IconData icon) => ListTile(
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(name),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onChoose(id),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(SdSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: SdSpace.md),
            Text(l10n.lockWhoIsUsing, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            if ((error ?? '').isNotEmpty) ...[
              const SizedBox(height: SdSpace.sm),
              Text(error!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: SdColors.of(context).absent)),
            ],
            const SizedBox(height: SdSpace.lg),
            SdCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                person('', l10n.staffAdminName, l10n.lockAdminSubtitle, Icons.admin_panel_settings_outlined),
                for (final s in staff) ...[
                  const Divider(indent: SdSpace.lg),
                  person(s.id, s.name, s.roleLabel, Icons.person_outline),
                ],
              ]),
            ),
            if (fingerprint != null) ...[
              const SizedBox(height: SdSpace.lg),
              Center(child: fingerprint!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Choose a PIN (twice), then see the recovery code once.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key, required this.controller, this.isChange = false, this.onDone});

  final LockController controller;
  final bool isChange;
  final VoidCallback? onDone;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _first = '';
  String _pin = '';
  bool _confirming = false;
  String? _error;
  String? _recoveryCode;
  bool _written = false;

  Future<void> _next() async {
    final l10n = AppLocalizations.of(context);
    if (!_confirming) {
      setState(() {
        _first = _pin;
        _pin = '';
        _confirming = true;
        _error = null;
      });
      return;
    }
    if (_pin != _first) {
      setState(() {
        _pin = '';
        _first = '';
        _confirming = false;
        _error = l10n.pinMismatch;
      });
      return;
    }
    if (widget.isChange && widget.controller.hasPin) {
      await widget.controller.store.changePin(_pin);
      widget.controller.pinSaved();
      widget.onDone?.call();
      return;
    }
    final code = await widget.controller.store.setPin(_pin);
    setState(() => _recoveryCode = code);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (_recoveryCode != null) {
      return Scaffold(
        body: SafeArea(
          child: SdPage(children: [
            Icon(Icons.key_outlined, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: SdSpace.md),
            Text(l10n.recoveryTitle, style: theme.textTheme.headlineSmall),
            const SizedBox(height: SdSpace.md),
            Text(l10n.recoveryExplain),
            const SizedBox(height: SdSpace.xl),
            SdCard(
              child: SelectableText(
                _recoveryCode!,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 2, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: SdSpace.lg),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.recoveryWritten),
              value: _written,
              onChanged: (v) => setState(() => _written = v ?? false),
            ),
            const SizedBox(height: SdSpace.lg),
            SdButton(
              label: l10n.continueLabel,
              expand: true,
              onPressed: _written
                  ? () {
                      widget.controller.pinSaved();
                      widget.onDone?.call();
                    }
                  : null,
            ),
          ]),
        ),
      );
    }
    return Scaffold(
      appBar: widget.isChange ? AppBar(title: Text(l10n.pinChange)) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(SdSpace.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pin_outlined, size: 40, color: theme.colorScheme.primary),
                  const SizedBox(height: SdSpace.md),
                  Text(_confirming ? l10n.pinConfirm : l10n.pinChoose, style: theme.textTheme.titleLarge),
                  const SizedBox(height: SdSpace.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Text(
                      _error ?? (widget.isChange ? l10n.pinChooseHint : l10n.pinRequiredExplain),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: _error == null ? null : SdColors.of(context).absent),
                    ),
                  ),
                  const SizedBox(height: SdSpace.xl),
                  PinPad(value: _pin, onChanged: (v) => setState(() => _pin = v)),
                  const SizedBox(height: SdSpace.lg),
                  SdButton(label: l10n.next, onPressed: _pin.length >= 4 ? _next : null),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Forgot PIN: enter the recovery code, then choose a new PIN.
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, required this.controller});

  final LockController controller;

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _code = TextEditingController();
  String? _error;
  bool _verified = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_verified) {
      return PinSetupScreen(
        controller: widget.controller,
        isChange: true,
        onDone: () => Navigator.of(context).pop(),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.lockForgot)),
      body: SdPage(children: [
        Text(l10n.recoveryEnter),
        const SizedBox(height: SdSpace.lg),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: l10n.recoveryCodeLabel, errorText: _error, hintText: 'XXXX-XXXX-XXXX'),
        ),
        const SizedBox(height: SdSpace.lg),
        SdButton(
          label: l10n.next,
          onPressed: () async {
            final ok = await widget.controller.store.verifyRecoveryCode(_code.text);
            if (!mounted) return;
            setState(() {
              _verified = ok;
              _error = ok ? null : l10n.recoveryWrong;
            });
          },
        ),
        const SizedBox(height: SdSpace.xl),
        Text(l10n.recoveryLost, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
