import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'CloudDatabaseBackupService.dart';

class GoogleDriveAccountWidget extends StatefulWidget {
  const GoogleDriveAccountWidget({super.key});

  @override
  State<GoogleDriveAccountWidget> createState() => _GoogleDriveAccountWidgetState();
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
    if (signedIn) {
      setState(() {
        _account = _cloudService.account;
      });
    }
  }

  Future<void> _signIn() async {
    final success = await _cloudService.manualSignIn();
    if (success) {
      setState(() {
        _account = _cloudService.account;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erfolgreich verbunden')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login fehlgeschlagen')),
      );
    }
  }

  Future<void> _signOut() async {
    await _cloudService.googleSignIn.signOut();
    setState(() {
      _account = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Erfolgreich abgemeldet')),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            : const CircleAvatar(
          child: Icon(Icons.person_outline),
        ),
        title: Text(
          _account != null ? _account!.displayName ?? 'Kein Name' : 'Kein Account verbunden',
        ),
        subtitle: _account != null ? Text(_account!.email) : null,
        trailing: ElevatedButton(
          onPressed: _account != null ? _signOut : _signIn,
          child: Text(_account != null ? 'Abmelden' : 'Verbinden'),
        ),
      ),
    );
  }
}
