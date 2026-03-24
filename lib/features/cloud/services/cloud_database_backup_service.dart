import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../../core/data/database_helper.dart';

class CloudBackupOutcome {
  final bool success;
  final String messageKey;
  final Object? error;

  const CloudBackupOutcome._(this.success, this.messageKey, this.error);

  factory CloudBackupOutcome.success(String messageKey) {
    return CloudBackupOutcome._(true, messageKey, null);
  }

  factory CloudBackupOutcome.failure(String messageKey, {Object? error}) {
    return CloudBackupOutcome._(false, messageKey, error);
  }
}

class CloudDatabaseBackupService with WidgetsBindingObserver {
  static final CloudDatabaseBackupService _instance =
      CloudDatabaseBackupService._internal();

  factory CloudDatabaseBackupService() => _instance;

  CloudDatabaseBackupService._internal();

  static const _dbName = 'filme.db';
  static const _manifestName = 'cinecue_backup_manifest_v1.json';
  static const _maxBackups = 5;
  static const _autoBackupThreshold = 3;
  static const _prefsPendingChanges = 'cloud_backup_pending_changes';
  static const _prefsLastBackupAt = 'cloud_backup_last_backup_at';

  final GoogleSignIn googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  GoogleSignInAccount? account;
  drive.DriveApi? _driveApi;
  AppSettingsController? _settings;

  bool _bootstrapped = false;
  bool _isBackingUp = false;
  int _pendingChanges = 0;
  DateTime? _lastBackupAt;

  bool get isSignedIn => account != null;
  bool get isBusy => _isBackingUp;
  int get pendingChanges => _pendingChanges;
  DateTime? get lastBackupAt => _lastBackupAt;
  int get backupRetentionCount => _maxBackups;
  int get autoBackupThreshold => _autoBackupThreshold;

  Future<void> bootstrap(AppSettingsController settings) async {
    _settings = settings;

    if (!_bootstrapped) {
      WidgetsBinding.instance.addObserver(this);
      DatabaseHelper.setChangeListener(_onDatabaseChanged);
      _bootstrapped = true;
    }

    await _loadLocalState();
    await silentSignIn();
    await _maybeRestoreOnStartup();
  }

  Future<void> _loadLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    _pendingChanges = prefs.getInt(_prefsPendingChanges) ?? 0;
    final rawBackupAt = prefs.getString(_prefsLastBackupAt);
    if (rawBackupAt != null && rawBackupAt.isNotEmpty) {
      _lastBackupAt = DateTime.tryParse(rawBackupAt);
    }
  }

  Future<void> _saveLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsPendingChanges, _pendingChanges);
    if (_lastBackupAt != null) {
      await prefs.setString(
        _prefsLastBackupAt,
        _lastBackupAt!.toIso8601String(),
      );
    }
  }

  Future<bool> silentSignIn() async {
    try {
      account = await googleSignIn.signInSilently();
      if (account == null) {
        _driveApi = null;
        return false;
      }
      final authHeaders = await account!.authHeaders;
      _driveApi = drive.DriveApi(GoogleAuthClient(authHeaders));
      return true;
    } catch (_) {
      account = null;
      _driveApi = null;
      return false;
    }
  }

  Future<bool> manualSignIn() async {
    try {
      account = await googleSignIn.signIn();
      if (account == null) {
        _driveApi = null;
        return false;
      }
      final authHeaders = await account!.authHeaders;
      _driveApi = drive.DriveApi(GoogleAuthClient(authHeaders));
      return true;
    } catch (_) {
      account = null;
      _driveApi = null;
      return false;
    }
  }

  Future<void> signOut() async {
    await googleSignIn.signOut();
    account = null;
    _driveApi = null;
  }

  Future<void> _maybeRestoreOnStartup() async {
    final settings = _settings;
    if (settings == null || !settings.cloudAutoRestoreEnabled) return;
    if (!isSignedIn || _driveApi == null) return;

    try {
      final localCount = await DatabaseHelper.movieCount();
      if (localCount > 0) return;
      await restoreLatest();
    } catch (_) {
      // Startup restore is best-effort and should never block app start.
    }
  }

  void _onDatabaseChanged(DatabaseChangeType _) {
    _pendingChanges += 1;
    unawaited(_saveLocalState());
    _scheduleAutoBackupIfNeeded(reason: 'changes');
  }

  void _scheduleAutoBackupIfNeeded({required String reason}) {
    final settings = _settings;
    if (settings == null) return;
    if (!settings.cloudAutoBackupEnabled) return;
    if (_pendingChanges < _autoBackupThreshold) return;
    unawaited(backupNow(reason: reason));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }

    final settings = _settings;
    if (settings == null || !settings.cloudAutoBackupEnabled) return;
    if (_pendingChanges <= 0) return;
    unawaited(backupNow(reason: 'lifecycle'));
  }

  Future<CloudBackupOutcome> backupNow({
    String dbName = _dbName,
    String reason = 'manual',
  }) async {
    if (!isSignedIn || _driveApi == null) {
      return CloudBackupOutcome.failure('cloud_backup_not_signed_in');
    }
    if (_isBackingUp) {
      return CloudBackupOutcome.failure('cloud_backup_in_progress');
    }

    final dbFile = await _databaseFile(dbName);
    if (!dbFile.existsSync()) {
      return CloudBackupOutcome.failure('cloud_backup_db_missing');
    }

    _isBackingUp = true;
    try {
      final bytes = await dbFile.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      final nowUtc = DateTime.now().toUtc();
      final backupName = 'cinecue_backup_${_timestampForFile(nowUtc)}.db';

      final created = await _createFileInAppDataFolder(
        name: backupName,
        bytes: bytes,
        mimeType: 'application/octet-stream',
      );

      final manifest = await _loadManifest();
      final latestEntry = _BackupManifestEntry(
        fileId: created.id!,
        fileName: backupName,
        createdAtUtc: nowUtc.toIso8601String(),
        sha256: digest,
        sizeBytes: bytes.length,
        trigger: reason,
      );

      final merged = [
        latestEntry,
        ...manifest.entries.where(
          (entry) => entry.fileId != latestEntry.fileId,
        ),
      ];

      final keep = merged.take(_maxBackups).toList();
      final remove = merged.skip(_maxBackups).toList();
      for (final oldEntry in remove) {
        try {
          await _driveApi!.files.delete(oldEntry.fileId);
        } catch (_) {
          // Ignore delete failures for old backups.
        }
      }

      final updatedManifest = _BackupManifest(
        updatedAtUtc: nowUtc.toIso8601String(),
        entries: keep,
      );
      await _saveManifest(updatedManifest);

      _pendingChanges = 0;
      _lastBackupAt = nowUtc;
      await _saveLocalState();
      return CloudBackupOutcome.success('cloud_backup_success');
    } catch (error) {
      return CloudBackupOutcome.failure('cloud_backup_failed', error: error);
    } finally {
      _isBackingUp = false;
    }
  }

  Future<CloudBackupOutcome> restoreLatest({String dbName = _dbName}) async {
    if (!isSignedIn || _driveApi == null) {
      return CloudBackupOutcome.failure('cloud_backup_not_signed_in');
    }

    try {
      final manifest = await _loadManifest();
      if (manifest.entries.isEmpty) {
        return CloudBackupOutcome.failure('cloud_backup_no_backups');
      }

      final latest = manifest.entries.first;
      final bytes = await _downloadFileBytes(latest.fileId);
      final digest = sha256.convert(bytes).toString();
      if (digest != latest.sha256) {
        return CloudBackupOutcome.failure('cloud_backup_integrity_failed');
      }

      final dbFile = await _databaseFile(dbName);
      await DatabaseHelper.closeDb();
      await dbFile.writeAsBytes(bytes, flush: true);
      await DatabaseHelper.initDb();

      _pendingChanges = 0;
      await _saveLocalState();
      return CloudBackupOutcome.success('cloud_restore_success');
    } catch (error) {
      return CloudBackupOutcome.failure('cloud_restore_failed', error: error);
    }
  }

  Future<File> _databaseFile(String dbName) async {
    final dir = await getApplicationDocumentsDirectory();
    return File(join(dir.path, dbName));
  }

  String _timestampForFile(DateTime dateTimeUtc) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${dateTimeUtc.year}'
        '${two(dateTimeUtc.month)}'
        '${two(dateTimeUtc.day)}'
        'T'
        '${two(dateTimeUtc.hour)}'
        '${two(dateTimeUtc.minute)}'
        '${two(dateTimeUtc.second)}'
        '${three(dateTimeUtc.millisecond)}'
        'Z';
  }

  Future<drive.File> _createFileInAppDataFolder({
    required String name,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length);
    final file = drive.File()
      ..name = name
      ..parents = ['appDataFolder']
      ..mimeType = mimeType;
    return _driveApi!.files.create(file, uploadMedia: media);
  }

  Future<drive.File?> _findFileByName(String fileName) async {
    final escapedName = fileName.replaceAll("'", "\\'");
    final list = await _driveApi!.files.list(
      spaces: 'appDataFolder',
      q: "name='$escapedName' and trashed=false",
      $fields: 'files(id,name,createdTime,size,description)',
      pageSize: 10,
    );
    final files = list.files;
    if (files == null || files.isEmpty) return null;
    return files.first;
  }

  Future<Uint8List> _downloadFileBytes(String fileId) async {
    final stream =
        await _driveApi!.files.get(
              fileId,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<_BackupManifest> _loadManifest() async {
    final manifestFile = await _findFileByName(_manifestName);
    if (manifestFile == null) return _BackupManifest.empty();

    try {
      final raw = await _downloadFileBytes(manifestFile.id!);
      final jsonMap = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      return _BackupManifest.fromJson(jsonMap);
    } catch (_) {
      return _BackupManifest.empty();
    }
  }

  Future<void> _saveManifest(_BackupManifest manifest) async {
    final bytes = utf8.encode(jsonEncode(manifest.toJson()));
    final existing = await _findFileByName(_manifestName);
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length);

    if (existing != null) {
      final updateFile = drive.File()
        ..name = _manifestName
        ..mimeType = 'application/json';
      await _driveApi!.files.update(
        updateFile,
        existing.id!,
        uploadMedia: media,
      );
      return;
    }

    final createFile = drive.File()
      ..name = _manifestName
      ..parents = ['appDataFolder']
      ..mimeType = 'application/json';
    await _driveApi!.files.create(createFile, uploadMedia: media);
  }
}

class _BackupManifest {
  final String updatedAtUtc;
  final List<_BackupManifestEntry> entries;

  const _BackupManifest({required this.updatedAtUtc, required this.entries});

  factory _BackupManifest.empty() {
    return const _BackupManifest(updatedAtUtc: '', entries: []);
  }

  factory _BackupManifest.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    if (rawEntries is! List) return _BackupManifest.empty();
    return _BackupManifest(
      updatedAtUtc: (json['updatedAtUtc'] as String?) ?? '',
      entries: rawEntries
          .whereType<Map<String, dynamic>>()
          .map(_BackupManifestEntry.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': 1,
      'updatedAtUtc': updatedAtUtc,
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }
}

class _BackupManifestEntry {
  final String fileId;
  final String fileName;
  final String createdAtUtc;
  final String sha256;
  final int sizeBytes;
  final String trigger;

  const _BackupManifestEntry({
    required this.fileId,
    required this.fileName,
    required this.createdAtUtc,
    required this.sha256,
    required this.sizeBytes,
    required this.trigger,
  });

  factory _BackupManifestEntry.fromJson(Map<String, dynamic> json) {
    return _BackupManifestEntry(
      fileId: (json['fileId'] as String?) ?? '',
      fileName: (json['fileName'] as String?) ?? '',
      createdAtUtc: (json['createdAtUtc'] as String?) ?? '',
      sha256: (json['sha256'] as String?) ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      trigger: (json['trigger'] as String?) ?? 'manual',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fileId': fileId,
      'fileName': fileName,
      'createdAtUtc': createdAtUtc,
      'sha256': sha256,
      'sizeBytes': sizeBytes,
      'trigger': trigger,
    };
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }

  @override
  void close() {
    _client.close();
  }
}
