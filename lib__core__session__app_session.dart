/// Who is working, on which institution, from which device.
/// Every write records these, which is what makes audit and sync possible.
class AppSession {
  const AppSession({
    required this.organizationId,
    required this.deviceId,
    required String userId,
    this.activeUserId,
  }) : _userId = userId;

  final String organizationId;
  final String deviceId;
  final String _userId;

  /// The staff member logged in right now (null for the administrator).
  /// Read on every write, so a change of user needs no new session.
  final String? Function()? activeUserId;

  String get userId => activeUserId?.call() ?? _userId;
}
