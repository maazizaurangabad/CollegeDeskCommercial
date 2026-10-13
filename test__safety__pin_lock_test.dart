import 'package:flutter_test/flutter_test.dart';
import 'package:shiksha_desk/core/security/pin_lock_store.dart';
import 'package:shiksha_desk/core/security/secret_store.dart';

void main() {
  late MemorySecretStore secrets;
  late DateTime now;
  late PinLockStore store;

  setUp(() {
    secrets = MemorySecretStore();
    now = DateTime(2026, 10, 9, 10);
    store = PinLockStore(secrets, clock: () => now);
  });

  test('the PIN itself is never stored; the right PIN opens, a wrong one does not', () async {
    final code = await store.setPin('4821');
    expect(code, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$')));
    expect(secrets.values.values.any((v) => v.contains('4821')), isFalse);
    expect(await store.verifyPin('4821'), isTrue);
    expect(await store.verifyPin('1111'), isFalse);
    expect(await store.pinLength(), 4);
  });

  test('after five wrong tries the user must wait, and the wait grows', () async {
    await store.setPin('123456');
    for (var i = 0; i < 4; i++) {
      expect(await store.verifyPin('000000'), isFalse);
    }
    expect(await store.blockedUntil(), isNull);
    await store.verifyPin('000000');
    expect(await store.blockedUntil(), now.add(const Duration(seconds: 30)));
    // Even the right PIN is refused while blocked.
    expect(await store.verifyPin('123456'), isFalse);
    now = now.add(const Duration(seconds: 31));
    await store.verifyPin('000000');
    expect(await store.blockedUntil(), now.add(const Duration(seconds: 60)));
    now = now.add(const Duration(seconds: 61));
    expect(await store.verifyPin('123456'), isTrue);
    expect(await store.blockedUntil(), isNull);
  });

  test('the recovery code works with any spacing or case, and allows a new PIN', () async {
    final code = await store.setPin('2580');
    expect(await store.verifyRecoveryCode(code.toLowerCase().replaceAll('-', ' ')), isTrue);
    expect(await store.verifyRecoveryCode('AAAA-BBBB-CCCC'), isFalse);
    await store.changePin('97531');
    expect(await store.verifyPin('97531'), isTrue);
    expect(await store.pinLength(), 5);
    // The recovery code still works after a PIN change.
    expect(await store.verifyRecoveryCode(code), isTrue);
  });

  test('only 4 to 6 digit PINs are accepted', () async {
    expect(PinLockStore.isValidPin('123'), isFalse);
    expect(PinLockStore.isValidPin('1234567'), isFalse);
    expect(PinLockStore.isValidPin('12a4'), isFalse);
    expect(() => store.setPin('12'), throwsArgumentError);
  });

  test('lock settings are remembered', () async {
    expect(await store.timeoutMinutes(), PinLockStore.defaultTimeoutMinutes);
    await store.setTimeoutMinutes(15);
    await store.setBiometricEnabled(true);
    expect(await store.timeoutMinutes(), 15);
    expect(await store.biometricEnabled(), isTrue);
  });
}
