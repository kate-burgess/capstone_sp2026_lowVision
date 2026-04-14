import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_colors.dart';
import 'grocery_ui.dart';
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

  static const _seed = Color(0xFF6D5EF5);

  static final _colorScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
    surface: kBrandCanvas,
    onSurface: const Color(0xFFF5F7FA),
    primary: const Color(0xFF6D5EF5),
    onPrimary: const Color(0xFFF5F7FA),
    secondary: const Color(0xFF3AE4C2),
    onSecondary: const Color(0xFF232733),
    error: const Color(0xFFFF6B6B),
    onError: const Color(0xFF232733),
    surfaceContainerHighest: const Color(0xFF1A1D24),
  );

  static const _baseTextTheme = TextTheme(
    displayLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
    headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
    titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 22),
    bodyMedium: TextStyle(fontSize: 20),
    labelLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
  );

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.soraTextTheme(_baseTextTheme).apply(
      bodyColor: const Color(0xFFF5F7FA),
      displayColor: const Color(0xFFF5F7FA),
    );
    return MaterialApp(
      title: 'Low Vision Daily Companion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: _colorScheme,
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: OpenUpwardsPageTransitionsBuilder(),
            TargetPlatform.fuchsia: OpenUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: OpenUpwardsPageTransitionsBuilder(),
            TargetPlatform.windows: OpenUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
        textTheme: textTheme,
        fontFamilyFallback: const ['Atkinson Hyperlegible', 'Roboto'],
        scaffoldBackgroundColor: kBrandCanvas,
        appBarTheme: AppBarTheme(
          backgroundColor: kBrandCanvas,
          foregroundColor: Colors.white,
          titleTextStyle: textTheme.titleLarge?.copyWith(color: Colors.white),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6D5EF5),
            foregroundColor: const Color(0xFFF5F7FA),
            elevation: 0,
            shadowColor: const Color(0xFF6D5EF5).withValues(alpha: 0.45),
            minimumSize: const Size(double.infinity, 56),
            textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF6D5EF5),
            side: const BorderSide(color: Color(0xFF6D5EF5), width: 2),
            minimumSize: const Size(double.infinity, 56),
            textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: const Color(0xFF6D5EF5),
          foregroundColor: const Color(0xFFF5F7FA),
          elevation: 4,
          highlightElevation: 8,
          largeSizeConstraints:
              const BoxConstraints.tightFor(width: 72, height: 72),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1D24),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          labelStyle: const TextStyle(fontSize: 20, color: Color(0xFFC2C7D0)),
          hintStyle: const TextStyle(fontSize: 20, color: Color(0xFFC2C7D0)),
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
            borderSide: const BorderSide(color: Color(0xFF6D5EF5), width: 2),
          ),
          errorStyle: const TextStyle(fontSize: 18, color: Color(0xFFFF6B6B)),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1D24),
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF1A1D24),
          selectedColor: const Color(0xFF6D5EF5).withValues(alpha: 0.3),
          labelStyle: const TextStyle(fontSize: 18, color: Colors.white),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          minVerticalPadding: 12,
          titleTextStyle: TextStyle(fontSize: 22, color: Colors.white),
          subtitleTextStyle: TextStyle(fontSize: 18, color: Colors.white70),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF6D5EF5);
            }
            return Colors.white24;
          }),
          checkColor: WidgetStateProperty.all(const Color(0xFFF5F7FA)),
          side: const BorderSide(color: Colors.white54, width: 2),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF1A1D24),
          titleTextStyle:
              textTheme.headlineMedium?.copyWith(color: Colors.white),
          contentTextStyle:
              textTheme.bodyLarge?.copyWith(color: Colors.white, fontSize: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1A1D24),
          contentTextStyle: const TextStyle(fontSize: 20, color: Colors.white),
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
    return Scaffold(
      body: GroceryAmbientBackdrop(
        child: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
