import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:shiksha_desk/app/startup/app_bootstrap.dart';
import 'package:shiksha_desk/app/startup/startup_state.dart';
import 'package:shiksha_desk/core/database/app_database.dart';
import 'package:shiksha_desk/core/security/field_cipher.dart';
import 'package:shiksha_desk/core/session/app_session.dart';
import 'package:shiksha_desk/platform/modules/module_providers.dart';

const testSession = AppSession(organizationId: 'org-test-0001', deviceId: 'device-test', userId: 'user-test');

/// A fixed key, for tests only.
final testCipher = FieldCipher(List<int>.generate(64, (i) => i));

AppDatabase newMemoryDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
}

Future<StartupState> newTestStartup({int demoStudentCount = 30}) {
  return AppBootstrap.loadState(
    db: newMemoryDatabase(),
    session: testSession,
    registry: buildModuleRegistry(),
    encrypted: false,
    fieldCipher: testCipher,
    demoStudentCount: demoStudentCount,
  );
}
