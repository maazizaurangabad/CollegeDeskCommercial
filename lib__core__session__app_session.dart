/// Who is working, on which institution, from which device.
/// Every write records these, which is what makes audit and sync possible.
class AppSession {
  const AppSession({required this.organizationId, required this.deviceId, required this.userId});

  final String organizationId;
  final String deviceId;
  final String userId;
}
