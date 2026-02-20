import 'dart:async';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:convert';

import '../app/firebase_config.dart';

class AuthService {
  AuthService._({required FirebaseAuth auth, User? initialUser})
      : _auth = auth,
        _user = initialUser;

  factory AuthService.create({required FirebaseAuth auth, User? initialUser}) {
    return AuthService._(
      auth: auth,
      initialUser: initialUser ?? auth.currentUser,
    );
  }

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  late final StreamSubscription<User?> _authSubscription;
  User? _user;

  bool get isAuthenticated => _user != null;
  bool get skipAuth => FirebaseConfig.skipAuth;
  String? get userEmail => _user?.email;
  String? get userId => _user?.uid;
  bool get isDevUnauthed => skipAuth && _user == null;

  /// Subscribes to auth state changes. [onChanged] is called each time
  /// the user changes (after the internal user field is updated).
  void bind(void Function() onChanged) {
    _authSubscription = _auth.authStateChanges().listen((user) {
      _user = user;
      onChanged();
    });
  }

  /// Binds to an empty stream — used in tests to prevent real auth callbacks.
  void bindNoop() {
    _authSubscription = const Stream<User?>.empty().listen((_) {});
  }

  Future<void> maybeAutoSignIn() async {
    if (!FirebaseConfig.skipAuth || _user != null) return;
    final email = FirebaseConfig.devEmail;
    final password = FirebaseConfig.devPassword;
    if (email.isEmpty || password.isEmpty) return;
    try {
      final response = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      _user = response.user;
    } on FirebaseAuthException {
      return;
    } catch (_) {
      return;
    }
  }

  Future<UserCredential> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  Future<UserCredential?> signInWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: auth.idToken,
      accessToken: auth.accessToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<UserCredential?> signInWithApple() async {
    final isAvailable = await SignInWithApple.isAvailable();
    if (!isAvailable) {
      throw FirebaseAuthException(
        code: 'apple-sign-in-unavailable',
        message: 'Sign in with Apple is not available on this device.',
      );
    }
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'apple-sign-in-failed',
        message: 'Unable to retrieve Apple identity token.',
      );
    }
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
    );
    return _auth.signInWithCredential(oauthCredential);
  }

  void dispose() {
    _authSubscription.cancel();
  }
}

String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List<String>.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

String _sha256ofString(String input) {
  final bytes = utf8.encode(input);
  final digest = sha256.convert(bytes);
  return digest.toString();
}
