/// Authentication adapter.
///
/// Clerk SDK APIs changed across versions and currently fail this project's CI
/// build when loose dependency constraints resolve to incompatible releases.
/// This fallback keeps app compilation stable until SDK integration is updated.
class AuthService {
  AuthService._();

  factory AuthService.create() => AuthService._();

  bool get isAuthenticated => false;
  bool get isDevUnauthed => false;
  String? get userId => null;
  String? get userEmail => null;

  void bind(void Function() onChanged) {
    // No-op in fallback mode.
  }

  Future<void> signOut() async {}

  Future<void> deleteAccount() async {
    throw StateError('Account deletion requires sign in.');
  }

  Future<String> requireClerkUserIdOrThrow() async {
    throw StateError('Sign in required to continue.');
  }

  void dispose() {}
}

String? currentClerkUserId() => null;

Future<String> requireClerkUserIdOrThrow() async {
  throw StateError('Sign in required to continue.');
}
