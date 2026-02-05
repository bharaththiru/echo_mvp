import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_scope.dart';
import '../theme/echo_theme.dart';
import '../utils/responsive.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/echo_components.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final appState = AppScope.of(context);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _statusMessage = 'Enter both email and password.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _statusIsError = false;
    });

    try {
      if (_isSignUp) {
        await appState.signUp(email: email, password: password);
      } else {
        await appState.signInWithPassword(email: email, password: password);
      }
      if (!mounted) {
        return;
      }
      context.go('/listen');
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.message ?? 'Unable to sign in right now.';
        _statusIsError = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Unable to sign in right now.';
        _statusIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    final appState = AppScope.of(context);
    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _statusIsError = false;
    });
    try {
      final result = await appState.signInWithGoogle();
      if (!mounted) {
        return;
      }
      if (result == null) {
        setState(() => _isLoading = false);
        return;
      }
      context.go('/listen');
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.message ?? 'Unable to sign in right now.';
        _statusIsError = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Unable to sign in right now.';
        _statusIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithApple() async {
    final appState = AppScope.of(context);
    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _statusIsError = false;
    });
    try {
      final result = await appState.signInWithApple();
      if (!mounted) {
        return;
      }
      if (result == null) {
        setState(() => _isLoading = false);
        return;
      }
      context.go('/listen');
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.message ?? 'Unable to sign in right now.';
        _statusIsError = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Unable to sign in right now.';
        _statusIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _statusMessage = null;
      _statusIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.echo;
    final title = _isSignUp ? 'Create your account' : 'Welcome back';
    final actionLabel = _isSignUp ? 'Create account' : 'Sign in';
    final toggleLabel = _isSignUp
        ? 'Already have an account? Sign in'
        : 'New here? Create an account';
    const showSocialSignIn = false;
    final showApple = showSocialSignIn && Platform.isIOS;

    return AppScaffold(
      child: SingleChildScrollView(
        padding: EchoLayout.pagePadding(
          context,
          top: 8,
          bottom: 8,
          includeBottomSafeArea: true,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.displaySmall),
            const SizedBox(height: 12),
            Text(
              'Save your voice notes and sync across devices.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: tokens.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            EchoCard(
              padding: const EdgeInsets.all(20),
              radius: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EchoInput(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    labelText: 'Email',
                    hintText: 'you@example.com',
                  ),
                  const SizedBox(height: 12),
                  EchoInput(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _statusIsError
                            ? tokens.danger
                            : tokens.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  EchoPrimaryButton(
                    label: actionLabel,
                    isLoading: _isLoading,
                    onPressed: _submit,
                  ),
                  if (showSocialSignIn) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: SizedBox(height: 1)),
                        const SizedBox(width: 12),
                        Text(
                          'or',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(child: SizedBox(height: 1)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata),
                        label: const Text('Continue with Google'),
                      ),
                    ),
                    if (showApple) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _signInWithApple,
                          icon: const Icon(Icons.apple),
                          label: const Text('Continue with Apple'),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _isLoading ? null : _toggleMode,
                    child: Text(toggleLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
