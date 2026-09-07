/// Abstract interface for providing an auth token.
///
/// Implement this in your app (e.g. using SharedPreferences or
/// flutter_secure_storage) and pass the instance to [ApiClient].
abstract class TokenStorage {
  Future<String?> getToken();
}
