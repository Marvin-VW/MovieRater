import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsController extends ChangeNotifier {
  static const _darkModeKey = 'dark_mode_enabled';
  static const _languageKey = 'language_code';
  static const _omdbApiKey = 'omdb_api_key';
  static const _tmdbApiKey = 'tmdb_api_key';
  static const _setupCompletedKey = 'setup_completed';
  static const _autoMetadataKey = 'auto_metadata_enabled';
  static const _externalRatingsKey = 'external_ratings_enabled';
  static const _customCategoriesKey = 'custom_categories';

  bool _darkModeEnabled = false;
  String _languageCode = 'de';
  String _omdbApiKeyValue = '';
  String _tmdbApiKeyValue = '';
  bool _setupCompleted = false;
  bool _autoMetadataEnabled = true;
  bool _externalRatingsEnabled = true;
  List<String> _customCategories = const [];

  bool get darkModeEnabled => _darkModeEnabled;
  String get languageCode => _languageCode;
  String get omdbApiKey => _omdbApiKeyValue;
  String get tmdbApiKey => _tmdbApiKeyValue;
  bool get setupCompleted => _setupCompleted;
  bool get autoMetadataEnabled => _autoMetadataEnabled;
  bool get externalRatingsEnabled => _externalRatingsEnabled;
  List<String> get customCategories => List.unmodifiable(_customCategories);
  ThemeMode get themeMode =>
      _darkModeEnabled ? ThemeMode.dark : ThemeMode.light;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _darkModeEnabled = prefs.getBool(_darkModeKey) ?? false;
    _languageCode = prefs.getString(_languageKey) ?? 'de';
    _omdbApiKeyValue = prefs.getString(_omdbApiKey) ?? '';
    _tmdbApiKeyValue = prefs.getString(_tmdbApiKey) ?? '';
    _setupCompleted =
        prefs.getBool(_setupCompletedKey) ??
        (_omdbApiKeyValue.isNotEmpty || _tmdbApiKeyValue.isNotEmpty);
    _autoMetadataEnabled = prefs.getBool(_autoMetadataKey) ?? true;
    _externalRatingsEnabled = prefs.getBool(_externalRatingsKey) ?? true;
    _customCategories = prefs.getStringList(_customCategoriesKey) ?? const [];
    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) async {
    if (_darkModeEnabled == enabled) return;
    _darkModeEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, enabled);
    notifyListeners();
  }

  Future<void> setLanguageCode(String languageCode) async {
    if (_languageCode == languageCode) return;
    _languageCode = languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
    notifyListeners();
  }

  Future<void> setOmdbApiKey(String value) async {
    final trimmed = value.trim();
    if (_omdbApiKeyValue == trimmed) return;
    _omdbApiKeyValue = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_omdbApiKey, trimmed);
    notifyListeners();
  }

  Future<void> setTmdbApiKey(String value) async {
    final trimmed = value.trim();
    if (_tmdbApiKeyValue == trimmed) return;
    _tmdbApiKeyValue = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tmdbApiKey, trimmed);
    notifyListeners();
  }

  Future<void> setSetupCompleted(bool completed) async {
    if (_setupCompleted == completed) return;
    _setupCompleted = completed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupCompletedKey, completed);
    notifyListeners();
  }

  Future<void> setAutoMetadataEnabled(bool enabled) async {
    if (_autoMetadataEnabled == enabled) return;
    _autoMetadataEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoMetadataKey, enabled);
    notifyListeners();
  }

  Future<void> setExternalRatingsEnabled(bool enabled) async {
    if (_externalRatingsEnabled == enabled) return;
    _externalRatingsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_externalRatingsKey, enabled);
    notifyListeners();
  }

  Future<void> addCustomCategory(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    final lower = trimmed.toLowerCase();
    final exists = _customCategories.any((c) => c.toLowerCase() == lower);
    if (exists) return;

    _customCategories = [..._customCategories, trimmed];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customCategoriesKey, _customCategories);
    notifyListeners();
  }

  Future<void> removeCustomCategory(String value) async {
    final lower = value.trim().toLowerCase();
    if (lower.isEmpty) return;

    final updated = _customCategories
        .where((c) => c.toLowerCase() != lower)
        .toList();
    if (updated.length == _customCategories.length) return;

    _customCategories = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customCategoriesKey, _customCategories);
    notifyListeners();
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettingsController> {
  final AppSettingsController controller;

  const AppSettingsScope({
    super.key,
    required this.controller,
    required super.child,
  }) : super(notifier: controller);

  static AppSettingsController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'AppSettingsScope not found in widget tree');
    return scope!.controller;
  }
}
