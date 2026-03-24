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

  static const _seed = Color(0xFF00E5FF);

  static final _colorScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
    surface: const Color(0xFF121212),
    onSurface: Colors.white,
    primary: const Color(0xFF00E5FF),
    onPrimary: Colors.black,
    secondary: const Color(0xFFFFD54F),
    onSecondary: Colors.black,
    error: const Color(0xFFFF6E6E),
    onError: Colors.black,
    surfaceContainerHighest: const Color(0xFF1E1E2C),
  );

  static const _textTheme = TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
    headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 20),
    bodyMedium: TextStyle(fontSize: 18),
    labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Low Vision Daily Companion',
      theme: ThemeData(
        colorScheme: _colorScheme,
        useMaterial3: true,
        textTheme: _textTheme,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF1E1E2C),
          foregroundColor: Colors.white,
          titleTextStyle: _textTheme.titleLarge?.copyWith(color: Colors.white),
          centerTitle: true,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 56),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF00E5FF),
            side: const BorderSide(color: Color(0xFF00E5FF), width: 2),
            minimumSize: const Size(double.infinity, 56),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF00E5FF),
          foregroundColor: Colors.black,
          largeSizeConstraints: BoxConstraints.tightFor(width: 72, height: 72),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1E2C),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          labelStyle: const TextStyle(fontSize: 18, color: Colors.white70),
          hintStyle: const TextStyle(fontSize: 18, color: Colors.white38),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white24, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white24, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 2),
          ),
          errorStyle: const TextStyle(fontSize: 16, color: Color(0xFFFF6E6E)),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E2C),
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF1E1E2C),
          selectedColor: const Color(0xFF00E5FF).withOpacity(0.3),
          labelStyle: const TextStyle(fontSize: 16, color: Colors.white),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          minVerticalPadding: 12,
          titleTextStyle: TextStyle(fontSize: 20, color: Colors.white),
          subtitleTextStyle: TextStyle(fontSize: 16, color: Colors.white70),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF00E5FF);
            }
            return Colors.white24;
          }),
          checkColor: WidgetStateProperty.all(Colors.black),
          side: const BorderSide(color: Colors.white54, width: 2),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF1E1E2C),
          titleTextStyle: _textTheme.headlineMedium?.copyWith(color: Colors.white),
          contentTextStyle: _textTheme.bodyLarge?.copyWith(color: Colors.white),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1E1E2C),
          contentTextStyle: const TextStyle(fontSize: 18, color: Colors.white),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          behavior: SnackBarBehavior.floating,
        ),
        dividerTheme: const DividerThemeData(color: Colors.white12, thickness: 1),
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
