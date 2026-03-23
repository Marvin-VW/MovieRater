import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/localization/app_strings.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../cloud/widgets/google_drive_account_widget.dart';
import '../../movies/services/movie_metadata_service.dart';
import 'setup_wizard_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _omdbApiKeyController = TextEditingController();
  final _tmdbApiKeyController = TextEditingController();

  bool _didInit = false;
  bool _showApiKeys = false;
  bool _isTestingOmdb = false;
  bool _isTestingTmdb = false;
  bool? _omdbKeyValid;
  bool? _tmdbKeyValid;
  bool _showOmdbSection = false;
  bool _showTmdbSection = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;

    final settings = AppSettingsScope.of(context);
    _omdbApiKeyController.text = settings.omdbApiKey;
    _tmdbApiKeyController.text = settings.tmdbApiKey;
    _didInit = true;
  }

  @override
  void dispose() {
    _omdbApiKeyController.dispose();
    _tmdbApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _startSetupWizard() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const SetupWizardPage(launchedFromSettings: true),
      ),
    );

    if (result != true || !mounted) return;

    final settings = AppSettingsScope.of(context);
    setState(() {
      _omdbApiKeyController.text = settings.omdbApiKey;
      _tmdbApiKeyController.text = settings.tmdbApiKey;
      _omdbKeyValid = null;
      _tmdbKeyValid = null;
    });
  }

  Future<void> _saveApiKeys() async {
    final settings = AppSettingsScope.of(context);
    await settings.setOmdbApiKey(_omdbApiKeyController.text);
    await settings.setTmdbApiKey(_tmdbApiKeyController.text);
    await settings.setSetupCompleted(true);
    if (!mounted) return;

    setState(() {
      _omdbKeyValid = null;
      _tmdbKeyValid = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.text(context, 'settings_saved'))),
    );
  }

  Future<void> _testOmdbKey() async {
    if (_isTestingOmdb) return;

    setState(() {
      _isTestingOmdb = true;
    });

    final valid = await MovieMetadataService.validateOmdbKey(
      _omdbApiKeyController.text.trim(),
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
      _tmdbApiKeyController.text.trim(),
    );
    if (!mounted) return;

    setState(() {
      _isTestingTmdb = false;
      _tmdbKeyValid = valid;
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.text(context, 'link_open_error'))),
    );
  }

  Widget _keyStatus(
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
              color: isValid
                  ? Colors.green
                  : Theme.of(context).colorScheme.error,
              size: 16,
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

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    String t(String key) => AppStrings.text(context, key);

    return Scaffold(
      appBar: AppBar(title: Text(t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: Text(t('language')),
              subtitle: Text(t('language_desc')),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: settings.languageCode,
                  onChanged: (newLanguage) {
                    if (newLanguage != null) {
                      settings.setLanguageCode(newLanguage);
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                ),
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('metadata_setup_title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t('metadata_setup_desc'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _startSetupWizard,
                        icon: const Icon(Icons.slideshow_outlined),
                        label: Text(t('start_setup')),
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
                ],
              ),
            ),
          ),
          Card(
            child: ExpansionTile(
              initiallyExpanded: _showOmdbSection,
              onExpansionChanged: (expanded) {
                setState(() {
                  _showOmdbSection = expanded;
                });
              },
              leading: const Icon(Icons.key_outlined),
              title: Text(t('omdb_section_title')),
              subtitle: Text(t('omdb_api_hint')),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                TextField(
                  controller: _omdbApiKeyController,
                  obscureText: !_showApiKeys,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(labelText: t('omdb_api_key')),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          _openUrl('https://www.omdbapi.com/apikey.aspx'),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(t('open_omdb')),
                    ),
                    FilledButton.tonal(
                      onPressed: _saveApiKeys,
                      child: Text(t('save_api_key')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isTestingOmdb ? null : _testOmdbKey,
                      icon: _isTestingOmdb
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_outlined),
                      label: Text(
                        _isTestingOmdb ? t('testing_key') : t('test_key'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _keyStatus(
                  context,
                  isValid: _omdbKeyValid,
                  validText: t('omdb_key_valid'),
                  invalidText: t('omdb_key_invalid'),
                  invalidHint: t('omdb_key_invalid_tip'),
                ),
              ],
            ),
          ),
          Card(
            child: ExpansionTile(
              initiallyExpanded: _showTmdbSection,
              onExpansionChanged: (expanded) {
                setState(() {
                  _showTmdbSection = expanded;
                });
              },
              leading: const Icon(Icons.image_search_outlined),
              title: Text(t('tmdb_section_title')),
              subtitle: Text(t('tmdb_api_hint')),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                TextField(
                  controller: _tmdbApiKeyController,
                  obscureText: !_showApiKeys,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(labelText: t('tmdb_api_key')),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          _openUrl('https://www.themoviedb.org/settings/api'),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(t('open_tmdb')),
                    ),
                    FilledButton.tonal(
                      onPressed: _saveApiKeys,
                      child: Text(t('save_api_key')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isTestingTmdb ? null : _testTmdbKey,
                      icon: _isTestingTmdb
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_outlined),
                      label: Text(
                        _isTestingTmdb ? t('testing_key') : t('test_key'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _keyStatus(
                  context,
                  isValid: _tmdbKeyValid,
                  validText: t('tmdb_key_valid'),
                  invalidText: t('tmdb_key_invalid'),
                  invalidHint: t('tmdb_key_invalid_tip'),
                ),
              ],
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('auto_metadata_enabled')),
                    subtitle: Text(t('auto_metadata_desc')),
                    value: settings.autoMetadataEnabled,
                    onChanged: settings.setAutoMetadataEnabled,
                  ),
                  const Divider(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('external_ratings_enabled')),
                    subtitle: Text(t('external_ratings_desc')),
                    value: settings.externalRatingsEnabled,
                    onChanged: settings.setExternalRatingsEnabled,
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_none),
              title: Text(t('notifications')),
              subtitle: Text(t('notifications_desc')),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(t('app_version')),
              subtitle: const Text('1.2.0'),
            ),
          ),
          const GoogleDriveAccountWidget(),
        ],
      ),
    );
  }
}
