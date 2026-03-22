import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../app/localization/app_strings.dart';
import '../services/cloud_database_backup_service.dart';

class GoogleDriveAccountWidget extends StatefulWidget {
  const GoogleDriveAccountWidget({super.key});

  @override
  State<GoogleDriveAccountWidget> createState() =>
      _GoogleDriveAccountWidgetState();
}

class _GoogleDriveAccountWidgetState extends State<GoogleDriveAccountWidget> {
  final _cloudService = CloudDatabaseBackupService();
  GoogleSignInAccount? _account;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    final signedIn = await _cloudService.silentSignIn();
    if (!mounted || !signedIn) return;

    setState(() {
      _account = _cloudService.account;
    });
  }

  Future<void> _signIn() async {
    final success = await _cloudService.manualSignIn();
    if (!mounted) return;

    if (success) {
      setState(() {
        _account = _cloudService.account;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.text(context, 'connected_success'))),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.text(context, 'login_failed'))),
    );
  }

  Future<void> _signOut() async {
    await _cloudService.googleSignIn.signOut();
    if (!mounted) return;

    setState(() {
      _account = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.text(context, 'signed_out'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);

    return Card(
      child: ListTile(
        leading: _account != null
            ? CircleAvatar(
                backgroundImage: _account!.photoUrl != null
                    ? NetworkImage(_account!.photoUrl!)
                    : null,
                child: _account!.photoUrl == null
                    ? const Icon(Icons.person)
                    : null,
              )
            : const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(
          _account != null
              ? _account!.displayName ?? 'n/a'
              : t('no_account_connected'),
        ),
        subtitle: _account != null ? Text(_account!.email) : null,
        trailing: ElevatedButton(
          onPressed: _account != null ? _signOut : _signIn,
          child: Text(_account != null ? t('disconnect') : t('connect')),
        ),
      ),
    );
  }
}
