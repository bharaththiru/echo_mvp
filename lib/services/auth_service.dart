import 'dart:async';
import 'dart:io';

import 'package:clerk_auth/clerk_auth.dart';
import 'package:path_provider/path_provider.dart';

import '../config/clerk_config.dart';

/// Authentication adapter backed by Clerk.
class AuthService {
  AuthService._() {
    unawaited(_initialize());
  }

  factory AuthService.create() => AuthService._();

  final List<void Function()> _listeners = <void Function()>[];
  Auth? _auth;
  bool _initializing = false;

  Future<void> _initialize() async {
    if (_auth != null || _initializing) {
      return;
    }
    _initializing = true;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final auth = Auth(
        config: AuthConfig(publishableKey: ClerkConfig.publishableKey),
        persistor: await DefaultPersistor.create(
          storageDirectory: Directory(supportDir.path),
        ),
      );
      await auth.initialize();
      _auth = auth;
      _notify();
    } finally {
      _initializing = false;
    }
  }

  bool get isAuthenticated => _auth?.user != null;
  bool get isDevUnauthed => false;

  String? get userId {
    final user = _auth?.user;
    if (user == null) {
      return null;
    }
    final dynamic dynamicUser = user;
    return dynamicUser.id?.toString();
  }

  String? get userEmail {
    final user = _auth?.user;
    if (user == null) {
      return null;
    }
    final dynamic dynamicUser = user;

    final nestedPrimaryEmail = _readDynamicValue(
      target: _readDynamicValue(target: dynamicUser, memberName: 'primaryEmailAddress'),
      memberName: 'emailAddress',
    );
    final directEmail = _readDynamicValue(
      target: dynamicUser,
      memberName: 'emailAddress',
    );
    final fallbackIdentifier = _readDynamicValue(
      target: dynamicUser,
      memberName: 'identifier',
    );

    final candidate =
        nestedPrimaryEmail ?? directEmail ?? fallbackIdentifier;
    final resolved = candidate?.toString().trim();
    if (resolved == null || resolved.isEmpty) {
      return null;
    }
    return resolved;
  }

  void bind(void Function() onChanged) {
    _listeners.add(onChanged);
  }

  Future<void> signOut() async {
    await _initialize();
    await _auth?.signOut();
    _notify();
  }

  Future<void> refreshSession() async {
    final auth = _auth;
    _auth = null;
    auth?.terminate();
    await _initialize();
  }

  Future<void> deleteAccount() async {
    await _initialize();
    final user = _auth?.user;
    if (user == null) {
      throw StateError('Account deletion requires sign in.');
    }
    final dynamic dynamicUser = user;
    final deleteCall = dynamicUser.delete;
    if (deleteCall is Function) {
      await deleteCall();
      _notify();
      return;
    }
    throw StateError('Delete account is not available for this Clerk SDK build.');
  }

  Future<String> requireClerkUserIdOrThrow() async {
    await _initialize();
    final id = userId;
    if (id == null || id.isEmpty) {
      throw StateError('Sign in required to continue.');
    }
    return id;
  }

  void dispose() {
    final auth = _auth;
    _auth = null;
    auth?.terminate();
    _listeners.clear();
  }

  void _notify() {
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }
}

Object? _readDynamicValue({required dynamic target, required String memberName}) {
  if (target == null) {
    return null;
  }
  try {
    switch (memberName) {
      case 'primaryEmailAddress':
        return target.primaryEmailAddress;
      case 'emailAddress':
        return target.emailAddress;
      case 'identifier':
        return target.identifier;
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? currentClerkUserId() => null;

Future<String> requireClerkUserIdOrThrow() async {
  throw StateError('Sign in required to continue.');
}
