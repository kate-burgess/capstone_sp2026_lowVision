import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'take_picture_screen.dart';
import 'supabase_auth_screen.dart';
import 'grocery_list_screen.dart';
import 'profile_setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://pnalkdcpiijdbqeelpej.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBuYWxrZGNwaWlqZGJxZWVscGVqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5NTEzODMsImV4cCI6MjA4NzUyNzM4M30.IcqRR29B4MqF9SdQmmYGbkcz7mpeRQzIuBtSojqfemI',
  );

  await initCameras();
  runApp(const MyApp());
}

SupabaseClient get supabase => Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Low Vision OCR',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: supabase.auth.currentSession != null
          ? const _ProfileGate()
          : const SupabaseAuthScreen(),
    );
  }
}

/// On app launch, if the user already has a session, check whether they have
/// a profile row. If not, send them to profile setup first.
class _ProfileGate extends StatefulWidget {
  const _ProfileGate();

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            hasProfile ? const GroceryListScreen() : const ProfileSetupScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
