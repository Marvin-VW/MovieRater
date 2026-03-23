import 'package:flutter/material.dart';

import 'pages/home_gate_page.dart';
import 'settings/app_settings_controller.dart';

class MovieRaterApp extends StatelessWidget {
  final AppSettingsController settings;

  const MovieRaterApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      controller: settings,
      child: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          return MaterialApp(
            title: 'CineCue',
            debugShowCheckedModeBanner: false,
            themeMode: ThemeMode.dark,
            theme: _buildDarkTheme(),
            darkTheme: _buildDarkTheme(),
            home: const HomeGatePage(),
          );
        },
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    const accent = Color(0xFF1ED2E8);
    const action = Color(0xFFFFB322);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: accent,
          onPrimary: const Color(0xFF032028),
          secondary: action,
          onSecondary: const Color(0xFF3A2800),
          surface: const Color(0xFF131932),
          surfaceContainerHighest: const Color(0xFF1B2241),
          outlineVariant: const Color(0xFF313C69),
        );
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0A0F1F),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF151D38),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF2D3965)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF131C38),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2F3A69)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: accent, width: 1.2),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: action,
        foregroundColor: Color(0xFF3A2800),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: action,
          foregroundColor: const Color(0xFF3A2800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF2D3965)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
