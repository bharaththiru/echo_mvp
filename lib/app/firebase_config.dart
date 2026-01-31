class FirebaseConfig {
  static const skipAuth = bool.fromEnvironment(
    'SKIP_AUTH',
    defaultValue: false,
  );
  static const devEmail = String.fromEnvironment('DEV_EMAIL');
  static const devPassword = String.fromEnvironment('DEV_PASSWORD');
}
