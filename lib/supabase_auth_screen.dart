import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'grocery_list_screen.dart';
import 'grocery_ui.dart';
import 'main.dart';
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
        if (response.session == null && response.user != null) {
          try {
            final loginResponse = await supabase.auth.signInWithPassword(
              email: email,
              password: password,
            );
            if (loginResponse.session != null) {
              response = loginResponse;
            }
          } catch (_) {}
        }
      } else {
        response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }

      final session = response.session ?? supabase.auth.currentSession;
      final accessToken = session?.accessToken;

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

      bool hasProfile = false;
      try {
        final rows = await supabase
            .from('user_profiles')
            .select('id')
            .eq('id', supabase.auth.currentUser!.id)
            .limit(1);
        hasProfile = (rows as List).isNotEmpty;
      } catch (_) {}

      if (!mounted) return;

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
        title: Text(_isSignup ? 'Welcome' : 'Welcome Back'),
      ),
      body: GroceryAmbientBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: groceryMaxContentWidth(context),
              ),
              child: SingleChildScrollView(
                padding: groceryPagePadding(context).add(
                  const EdgeInsets.symmetric(vertical: 28),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: 'Low Vision Daily Companion',
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: kBrandPurpleMid.withValues(alpha: 0.35),
                                blurRadius: 32,
                                spreadRadius: -8,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset(
                              'assets/images/app_logo.png',
                              height: 140,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _isSignup
                            ? 'Create an account to get started'
                            : 'Sign in to continue',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 28),
                      if (_errorMessage != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error
                                .withValues(alpha: 0.15),
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
                      GroceryGlowButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.black,
                                ),
                              )
                            : Text(_isSignup ? 'Create Account' : 'Sign In'),
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
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _isSignup
                                ? 'Already have an account? Log in'
                                : 'Need an account? Sign up',
                            maxLines: 1,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
