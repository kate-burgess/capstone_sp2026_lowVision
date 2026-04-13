import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'grocery_list_screen.dart';
import 'main.dart';
import 'profile_setup_screen.dart';
import 'translated_text.dart';

class SupabaseAuthScreen extends StatefulWidget {
  const SupabaseAuthScreen({super.key});

  @override
  State<SupabaseAuthScreen> createState() => _SupabaseAuthScreenState();
}

class _SupabaseAuthScreenState extends State<SupabaseAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();

  bool _isSignup = true;
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      AuthResponse response;

      if (_isSignup) {
        response = await supabase.auth.signUp(
          email: email,
          password: password,
        );
        // If signup succeeded but returned no session, try to sign in
        // immediately (works when email confirmation is disabled).
        if (response.session == null && response.user != null) {
          try {
            final loginResponse = await supabase.auth.signInWithPassword(
              email: email,
              password: password,
            );
            if (loginResponse.session != null) {
              response = loginResponse;
            }
          } catch (_) {
            // Email confirmation is required — fall through to message below.
          }
        }
      } else {
        response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }

      final session = response.session ?? supabase.auth.currentSession;
      final accessToken = session?.accessToken;

      // No session means email confirmation is still required.
      if (accessToken == null) {
        if (_isSignup) {
          if (!mounted) return;
          setState(() {
            _errorMessage =
                'Sign up successful! Check your email to confirm, then log in.';
          });
          return;
        } else {
          throw const AuthException('No active session. Please log in again.');
        }
      }

      // Check whether this user already has a profile row.
      bool hasProfile = false;
      try {
        final rows = await supabase
            .from('user_profiles')
            .select('id')
            .eq('id', supabase.auth.currentUser!.id)
            .limit(1);
        hasProfile = (rows as List).isNotEmpty;
      } catch (_) {
        // If the check fails, fall through to profile setup anyway.
      }

      if (!mounted) return;

      // New users (no profile yet) → collect preferences first.
      // Returning users with a profile → go straight to grocery lists.
      if (!hasProfile) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GroceryListScreen()),
        );
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Tx(_isSignup ? 'Welcome' : 'Welcome Back'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: 'Low Vision Daily Companion',
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      height: 160,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Tx(
                    _isSignup
                        ? 'Create an account to get started'
                        : 'Sign in to continue',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white60),
                  ),
                  const SizedBox(height: 32),
                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_isSignup) ...[
                    TextFormField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 18),
                  ],
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    style: theme.textTheme.bodyLarge,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    style: theme.textTheme.bodyLarge,
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 3, color: Colors.black),
                          )
                        : Tx(_isSignup ? 'Create Account' : 'Sign In'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _isSignup = !_isSignup;
                              _errorMessage = null;
                            });
                          },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      textStyle: theme.textTheme.bodyMedium,
                    ),
                    child: Tx(
                      _isSignup
                          ? 'Already have an account? Log in'
                          : 'Need an account? Sign up',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

