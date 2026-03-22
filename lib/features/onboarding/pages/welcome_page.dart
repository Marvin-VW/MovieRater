import 'package:flutter/material.dart';

import '../../../app/localization/app_strings.dart';
import '../../settings/pages/setup_wizard_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  Future<void> _startSetup(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SetupWizardPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final startColor = isDark
        ? const Color(0xFF151515)
        : const Color(0xFFF7C948);
    final endColor = isDark ? const Color(0xFF242424) : const Color(0xFFF4B400);
    final bubbleColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.34);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [startColor, endColor],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -60,
              left: -30,
              child: _bubble(size: 180, color: bubbleColor),
            ),
            Positioned(
              top: 110,
              right: -55,
              child: _bubble(size: 170, color: bubbleColor),
            ),
            Positioned(
              bottom: 110,
              left: -45,
              child: _bubble(size: 150, color: bubbleColor),
            ),
            Positioned(
              bottom: -90,
              right: -20,
              child: _bubble(size: 220, color: bubbleColor),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Icon(
                      Icons.movie_filter_rounded,
                      size: 34,
                      color: isDark
                          ? const Color(0xFFF4B400)
                          : const Color(0xFF1E1E1E),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t('app_brand'),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t('welcome_subtitle'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.86)
                            : const Color(0xFF2A2A2A),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        t('welcome_note'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.9)
                              : const Color(0xFF2A2A2A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _startSetup(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: isDark
                              ? const Color(0xFFF4B400)
                              : const Color(0xFF111827),
                          foregroundColor: isDark
                              ? const Color(0xFF111827)
                              : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(t('welcome_setup_cta')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble({required double size, required Color color}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
