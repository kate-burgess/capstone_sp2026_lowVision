import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart';
import 'grocery_list_screen.dart';
import 'profile_setup_screen.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSignup ? 'Sign up' : 'Log in'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_isSignup) ...[
                    TextFormField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isSignup ? 'Sign up' : 'Log in'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _isSignup = !_isSignup;
                              _errorMessage = null;
                            });
                          },
                    child: Text(
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

