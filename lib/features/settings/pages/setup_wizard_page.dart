import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/localization/app_strings.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../movies/services/movie_metadata_service.dart';

class SetupWizardPage extends StatefulWidget {
  final bool launchedFromSettings;

  const SetupWizardPage({super.key, this.launchedFromSettings = false});

  @override
  State<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends State<SetupWizardPage> {
  final _pageController = PageController();
  final _omdbController = TextEditingController();
  final _tmdbController = TextEditingController();

  bool _didInit = false;
  int _pageIndex = 0;
  bool _showApiKeys = false;
  bool _isTestingOmdb = false;
  bool _isTestingTmdb = false;
  bool? _omdbKeyValid;
  bool? _tmdbKeyValid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;

    final settings = AppSettingsScope.of(context);
    _omdbController.text = settings.omdbApiKey;
    _tmdbController.text = settings.tmdbApiKey;
    _didInit = true;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _omdbController.dispose();
    _tmdbController.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.text(context, 'link_open_error'))),
    );
  }

  Future<void> _testOmdbKey() async {
    if (_isTestingOmdb) return;

    setState(() {
      _isTestingOmdb = true;
    });

    final valid = await MovieMetadataService.validateOmdbKey(
      _omdbController.text.trim(),
    );
    if (!mounted) return;

    setState(() {
      _isTestingOmdb = false;
      _omdbKeyValid = valid;
    });
  }

  Future<void> _testTmdbKey() async {
    if (_isTestingTmdb) return;

    setState(() {
      _isTestingTmdb = true;
    });

    final valid = await MovieMetadataService.validateTmdbKey(
      _tmdbController.text.trim(),
    );
    if (!mounted) return;

    setState(() {
      _isTestingTmdb = false;
      _tmdbKeyValid = valid;
    });
  }

  Future<void> _nextPage() async {
    if (_pageIndex >= 2) {
      await _finishSetup();
      return;
    }

    await _pageController.animateToPage(
      _pageIndex + 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _previousPage() async {
    if (_pageIndex <= 0) return;
    await _pageController.animateToPage(
      _pageIndex - 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finishSetup() async {
    final settings = AppSettingsScope.of(context);
    await settings.setOmdbApiKey(_omdbController.text);
    await settings.setTmdbApiKey(_tmdbController.text);
    await settings.setSetupCompleted(true);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.text(context, 'setup_done'))),
    );

    if (widget.launchedFromSettings) {
      Navigator.pop(context, true);
      return;
    }

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Widget _statusLine(
    BuildContext context, {
    required bool? isValid,
    required String validText,
    required String invalidText,
    String? invalidHint,
  }) {
    if (isValid == null) {
      return const SizedBox.shrink();
    }

    final isError = !isValid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isValid ? Icons.check_circle : Icons.error_outline,
              size: 16,
              color: isValid
                  ? Colors.green
                  : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                isValid ? validText : invalidText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        if (isError && invalidHint != null && invalidHint.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            invalidHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _featureBullet(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroPage(BuildContext context, String Function(String key) t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.movie_filter_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            t('setup_intro_title'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(t('setup_intro_desc')),
          const SizedBox(height: 14),
          _featureBullet(
            context,
            Icons.smartphone_outlined,
            t('setup_intro_local_only'),
          ),
          _featureBullet(
            context,
            Icons.key_outlined,
            t('setup_intro_omdb_info'),
          ),
          _featureBullet(
            context,
            Icons.image_outlined,
            t('setup_intro_tmdb_info'),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyPage(
    BuildContext context, {
    required String title,
    required String description,
    required String hint,
    required List<String> setupSteps,
    required String fieldLabel,
    required TextEditingController controller,
    required String openButtonLabel,
    required VoidCallback openAction,
    required VoidCallback testAction,
    required bool isTesting,
    required bool? isValid,
    required String validText,
    required String invalidText,
    String? invalidHint,
  }) {
    String t(String key) => AppStrings.text(context, key);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(description),
          const SizedBox(height: 10),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          ...setupSteps.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.circle, size: 7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(step)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: openAction,
                icon: const Icon(Icons.open_in_new),
                label: Text(openButtonLabel),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showApiKeys = !_showApiKeys;
                  });
                },
                icon: Icon(
                  _showApiKeys
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                label: Text(
                  t(_showApiKeys ? 'hide_api_keys' : 'show_api_keys'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: !_showApiKeys,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: fieldLabel),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: isTesting ? null : testAction,
                icon: isTesting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_outlined),
                label: Text(isTesting ? t('testing_key') : t('test_key')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _statusLine(
            context,
            isValid: isValid,
            validText: validText,
            invalidText: invalidText,
            invalidHint: invalidHint,
          ),
        ],
      ),
    );
  }

  Widget _buildPageDots(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = Theme.of(context).colorScheme.outlineVariant;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final isActive = index == _pageIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? activeColor : inactiveColor,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }

  Widget _buildBottomActions(
    BuildContext context,
    String Function(String key) t,
  ) {
    final isLastPage = _pageIndex == 2;
    final nextLabel = isLastPage ? t('finish_setup') : t('next');

    final backButton = OutlinedButton.icon(
      onPressed: _previousPage,
      icon: const Icon(Icons.arrow_back),
      label: Text(t('back')),
    );
    final nextButton = FilledButton.icon(
      onPressed: _nextPage,
      icon: Icon(isLastPage ? Icons.check : Icons.arrow_forward),
      label: Text(nextLabel),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            children: [
              if (_pageIndex > 0)
                SizedBox(width: double.infinity, child: backButton),
              if (_pageIndex > 0) const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: nextButton),
            ],
          );
        }

        return Row(
          children: [
            if (_pageIndex > 0) backButton,
            const Spacer(),
            nextButton,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final startColor = isDark
        ? const Color(0xFF141414)
        : const Color(0xFFF7C948);
    final endColor = isDark ? const Color(0xFF232323) : const Color(0xFFF4B400);
    final bubbleColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.28);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(t('setup_wizard_title')),
        automaticallyImplyLeading: widget.launchedFromSettings,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
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
            Positioned(top: -30, left: -20, child: _bubble(120, bubbleColor)),
            Positioned(top: 120, right: -36, child: _bubble(140, bubbleColor)),
            Positioned(
              bottom: 110,
              left: -40,
              child: _bubble(160, bubbleColor),
            ),
            Positioned(
              bottom: -70,
              right: -20,
              child: _bubble(190, bubbleColor),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF161B22)
                        : const Color(0xFFFFFBF0),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (page) {
                            setState(() {
                              _pageIndex = page;
                            });
                          },
                          children: [
                            _buildIntroPage(context, t),
                            _buildKeyPage(
                              context,
                              title: t('setup_step_1_title'),
                              description: t('setup_step_1_desc'),
                              hint: t('omdb_api_hint'),
                              setupSteps: [
                                t('omdb_setup_step_1'),
                                t('omdb_setup_step_2'),
                                t('omdb_setup_step_3'),
                              ],
                              fieldLabel: t('omdb_api_key'),
                              controller: _omdbController,
                              openButtonLabel: t('open_omdb'),
                              openAction: () => _openUrl(
                                'https://www.omdbapi.com/apikey.aspx',
                              ),
                              testAction: _testOmdbKey,
                              isTesting: _isTestingOmdb,
                              isValid: _omdbKeyValid,
                              validText: t('omdb_key_valid'),
                              invalidText: t('omdb_key_invalid'),
                              invalidHint: t('omdb_key_invalid_tip'),
                            ),
                            _buildKeyPage(
                              context,
                              title: t('setup_step_2_title'),
                              description: t('setup_step_2_desc'),
                              hint: t('tmdb_api_hint'),
                              setupSteps: [
                                t('tmdb_setup_step_1'),
                                t('tmdb_setup_step_2'),
                                t('tmdb_setup_step_3'),
                              ],
                              fieldLabel: t('tmdb_api_key'),
                              controller: _tmdbController,
                              openButtonLabel: t('open_tmdb'),
                              openAction: () => _openUrl(
                                'https://www.themoviedb.org/settings/api',
                              ),
                              testAction: _testTmdbKey,
                              isTesting: _isTestingTmdb,
                              isValid: _tmdbKeyValid,
                              validText: t('tmdb_key_valid'),
                              invalidText: t('tmdb_key_invalid'),
                              invalidHint: t('tmdb_key_invalid_tip'),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Column(
                          children: [
                            _buildPageDots(context),
                            const SizedBox(height: 12),
                            _buildBottomActions(context, t),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
