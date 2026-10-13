import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/pin_lock_store.dart';

/// Decides when the app shows the lock screen or asks for a PIN to be set.
class LockController extends ChangeNotifier with WidgetsBindingObserver {
  LockController(this.store);

  final PinLockStore store;

  bool hasPin = false;
  bool locked = false;

  /// A real institution exists but no PIN is set yet.
  bool needsSetup = false;
  int timeoutMinutes = PinLockStore.defaultTimeoutMinutes;
  bool biometricEnabled = false;
  DateTime? _backgroundSince;

  Future<void> init({required bool pinRequired}) async {
    hasPin = await store.hasPin();
    timeoutMinutes = await store.timeoutMinutes();
    biometricEnabled = await store.biometricEnabled();
    locked = hasPin;
    needsSetup = pinRequired && !hasPin;
    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundSince ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundSince;
      _backgroundSince = null;
      if (hasPin && !locked && since != null && DateTime.now().difference(since).inMinutes >= timeoutMinutes) {
        locked = true;
        notifyListeners();
      }
    }
  }

  /// Called when a real institution is created or opened.
  void requirePin() {
    if (!hasPin && !needsSetup) {
      needsSetup = true;
      notifyListeners();
    }
  }

  void unlock() {
    locked = false;
    notifyListeners();
  }

  void lockNow() {
    if (!hasPin) return;
    locked = true;
    notifyListeners();
  }

  void pinSaved() {
    hasPin = true;
    needsSetup = false;
    locked = false;
    notifyListeners();
  }

  void pinRemoved() {
    hasPin = false;
    locked = false;
    notifyListeners();
  }

  Future<void> setTimeout(int minutes) async {
    await store.setTimeoutMinutes(minutes);
    timeoutMinutes = minutes;
    notifyListeners();
  }

  Future<void> setBiometric(bool enabled) async {
    await store.setBiometricEnabled(enabled);
    biometricEnabled = enabled;
    notifyListeners();
  }
}

/// The host owns the controller (it outlives institution switches), so this
/// is a plain provider; screens listen with ListenableBuilder.
final lockControllerProvider = Provider<LockController>(
  (ref) => throw UnimplementedError('lockControllerProvider must be overridden by WorkspaceHost'),
);
