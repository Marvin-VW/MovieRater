import 'package:flutter/material.dart';
import 'MovieHomepage.dart';
import 'CloudDatabaseBackupService.dart';


final cloudService = CloudDatabaseBackupService();


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cloudService = CloudDatabaseBackupService();
  final signedIn = await cloudService.silentSignIn();

  if (signedIn) {
    await cloudService.restoreDatabase('your_db_name.db');
  }

  runApp(MovieRater());
}

class MovieRater extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Movie Tracker',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: MovieListPage(),
    );
  }
}
