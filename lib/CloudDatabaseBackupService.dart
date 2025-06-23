import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class CloudDatabaseBackupService {
  static final CloudDatabaseBackupService _instance = CloudDatabaseBackupService._internal();
  factory CloudDatabaseBackupService() => _instance;
  CloudDatabaseBackupService._internal();

  final GoogleSignIn googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  GoogleSignInAccount? account;
  drive.DriveApi? _driveApi;

  bool get isSignedIn => account != null;

  Future<bool> silentSignIn() async {
    account = await googleSignIn.signInSilently();
    if (account != null) {
      final authHeaders = await account!.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      _driveApi = drive.DriveApi(authenticateClient);
      debugPrint("Silent Sign-In erfolgreich");
      return true;
    }
    debugPrint("Silent Sign-In fehlgeschlagen");
    return false;
  }

  Future<bool> manualSignIn() async {
    account = await googleSignIn.signIn();
    if (account != null) {
      final authHeaders = await account!.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      _driveApi = drive.DriveApi(authenticateClient);
      debugPrint("Manuelles Sign-In erfolgreich");
      return true;
    }
    debugPrint("Manuelles Sign-In fehlgeschlagen");
    return false;
  }

  Future<void> backupDatabase(String dbName) async {
    if (!isSignedIn || _driveApi == null) {
      debugPrint("Nicht eingeloggt — Backup abgebrochen");
      return;
    }

    final dbPath = await getDatabasesPath();
    final dbFile = File(join(dbPath, dbName));

    final files = await _driveApi!.files.list(spaces: 'appDataFolder');
    for (var file in files.files ?? []) {
      if (file.name == dbName) {
        await _driveApi!.files.delete(file.id!);
      }
    }

    final driveFile = drive.File()
      ..name = dbName
      ..parents = ['appDataFolder'];

    final media = drive.Media(dbFile.openRead(), dbFile.lengthSync());

    await _driveApi!.files.create(driveFile, uploadMedia: media);
    debugPrint("Backup erfolgreich hochgeladen");
  }

  Future<void> restoreDatabase(String dbName) async {
    if (!isSignedIn || _driveApi == null) {
      debugPrint("Nicht eingeloggt — Restore abgebrochen");
      return;
    }

    final dbPath = await getDatabasesPath();
    final localFile = File(join(dbPath, dbName));

    final files = await _driveApi!.files.list(
      spaces: 'appDataFolder',
      q: "name='$dbName'",
    );

    if (files.files == null || files.files!.isEmpty) {
      debugPrint("Kein Backup gefunden");
      return;
    }

    final backupFileId = files.files!.first.id!;
    final mediaStream = await _driveApi!.files.get(
      backupFileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final sink = localFile.openWrite();
    await mediaStream.stream.pipe(sink);
    debugPrint("Backup erfolgreich wiederhergestellt");
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
