import 'package:flutter/material.dart';

import 'app/movie_rater_app.dart';
import 'app/settings/app_settings_controller.dart';
import 'features/cloud/services/cloud_database_backup_service.dart';

final appSettings = AppSettingsController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await appSettings.load();

  final cloudService = CloudDatabaseBackupService();
  await cloudService.bootstrap(appSettings);

  runApp(MovieRaterApp(settings: appSettings));
}
