import 'dart:async';

import 'package:clerk_auth/clerk_auth.dart';

/// Thin adapter over Clerk so the app state can remain platform-agnostic.
class AuthService {
  AuthService._({required ClerkAuth clerkAuth}) : _clerkAuth = clerkAuth;

  factory AuthService.create() => AuthService._(clerkAuth: ClerkAuth.instance);

  final ClerkAuth _clerkAuth;
  StreamSubscription<AuthState>? _authSubscription;
  AuthState? _authState;

  bool get isAuthenticated => _authState?.isSignedIn ?? false;
  bool get isDevUnauthed => false;
  String? get userId => _authState?.user?.id;
  String? get userEmail => _authState?.user?.primaryEmailAddress?.emailAddress;

  void bind(void Function() onChanged) {
    _authState = _clerkAuth.authState;
    _authSubscription = _clerkAuth.authStateChanges.listen((state) {
      _authState = state;
      onChanged();
    });
  }

  Future<void> signOut() => _clerkAuth.signOut();

  Future<void> deleteAccount() async {
    final user = _authState?.user;
    if (user == null) {
      throw StateError('No signed in user.');
    }
    await user.delete();
  }

  Future<String> requireClerkUserIdOrThrow() async {
    final id = userId;
    if (id == null || id.isEmpty) {
      throw StateError('Sign in required to continue.');
    }
    return id;
  }

  void dispose() {
    _authSubscription?.cancel();
  }
}

String? currentClerkUserId() => ClerkAuth.instance.authState.user?.id;

Future<String> requireClerkUserIdOrThrow() async {
  final id = currentClerkUserId();
  if (id == null || id.isEmpty) {
    throw StateError('Sign in required to continue.');
  }
  return id;
}
