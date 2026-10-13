import '../audit/change_recorder.dart';
import '../session/app_session.dart';
import 'app_database.dart';

/// Base for every repository. Every query must filter on [orgId],
/// and every write must call [changes] inside its transaction.
abstract class OrgScopedRepository {
  OrgScopedRepository(this.db, this.session) : changes = ChangeRecorder(db, session);

  final AppDatabase db;
  final AppSession session;
  final ChangeRecorder changes;

  String get orgId => session.organizationId;

  DateTime now() => DateTime.now().toUtc();
}
