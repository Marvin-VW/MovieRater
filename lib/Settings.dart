import 'package:flutter/material.dart';
import 'GoogleDriveAccountWidget.dart';

class SettingsPage extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          ('settings'),
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [

            // Notifications Section
            SwitchListTile(
              title: Text('notifications'),
              subtitle: Text('enable_or_disable_notifications'),
              value: false,
              activeColor: Colors.black,
              onChanged: (bool value) {},
            ),
            Divider(),

            // Dark Mode Section
            SwitchListTile(
              title: Text('Dark Mode'),
              subtitle: Text('dark_mode_desc'),
              activeColor: Colors.black, value: false, onChanged: (bool value) { },
            ),
            Divider(),

            // Language Section
            ListTile(
              leading: Icon(Icons.language, color: Colors.black),
              title: Text('language'),
              subtitle: Text('change_language'),
              trailing: DropdownButton<String>(
                items: [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                ],
                onChanged: (String? newLanguage) {
                  if (newLanguage != null) {

                  }
                },
              ),
            ),
            Divider(),

            // Privacy and Security Section
            ListTile(
              leading: Icon(Icons.lock, color: Colors.black),
              title: Text('privacy_security'),
              subtitle: Text('privacy_settings'),
              trailing: Icon(Icons.arrow_forward_ios),
              onTap: () {},
            ),
            Divider(),

            // Help and Support Section
            ListTile(
              leading: Icon(Icons.help_outline, color: Colors.black),
              title: Text('help_support'),
              subtitle: Text('contact_us'),
              trailing: Icon(Icons.arrow_forward_ios),
              onTap: () {},
            ),
            Divider(),

            // App Version Section
            ListTile(
              leading: Icon(Icons.info_outline, color: Colors.black),
              title: Text('App Version'),
              subtitle: Text('0.1.27'),
              onTap: () {},
            ),
            Divider(),
            GoogleDriveAccountWidget(),
            Divider(),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Logout'),
          content: Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Logout'),
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/auth');
              },
            ),
          ],
        );
      },
    );
  }
}