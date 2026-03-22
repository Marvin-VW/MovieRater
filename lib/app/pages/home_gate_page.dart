import 'package:flutter/material.dart';

import '../../features/movies/pages/movie_list_page.dart';
import '../../features/onboarding/pages/welcome_page.dart';
import '../settings/app_settings_controller.dart';

class HomeGatePage extends StatelessWidget {
  const HomeGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    if (!settings.setupCompleted) {
      return const WelcomePage();
    }
    return const MovieListPage();
  }
}
