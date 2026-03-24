import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../app/localization/app_strings.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/data/database_helper.dart';
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
  bool _didBootstrap = false;

  @override
  void initState() {
    super.initState();
    _syncFromService();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didBootstrap) return;
    _didBootstrap = true;
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final settings = AppSettingsScope.of(context);
    await _cloudService.bootstrap(settings);
    if (!mounted) return;
    _syncFromService();
  }

  void _syncFromService() {
    if (!mounted) return;
    setState(() {
      _account = _cloudService.account;
    });
  }

  void _showOutcome(CloudBackupOutcome outcome) {
    String t(String key) => AppStrings.text(context, key);
    final key = outcome.messageKey;
    final message = t(key);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signIn() async {
    final success = await _cloudService.manualSignIn();
    if (!mounted) return;
    _syncFromService();
    final key = success ? 'connected_success' : 'login_failed';
    final text = AppStrings.text(context, key);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _signOut() async {
    await _cloudService.signOut();
    if (!mounted) return;
    _syncFromService();
    final text = AppStrings.text(context, 'signed_out');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _backupNow() async {
    final outcome = await _cloudService.backupNow(reason: 'manual');
    if (!mounted) return;
    _syncFromService();
    _showOutcome(outcome);
  }

  Future<void> _restoreLatest() async {
    String t(String key) => AppStrings.text(context, key);
    final localCount = await DatabaseHelper.movieCount();
    if (!mounted) return;

    if (localCount > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(t('cloud_restore_confirm_title')),
            content: Text(t('cloud_restore_confirm_message')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(t('cloud_restore_confirm_action')),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;
    }

    final outcome = await _cloudService.restoreLatest();
    if (!mounted) return;
    _syncFromService();
    _showOutcome(outcome);
  }

  String _lastBackupLabel(BuildContext context) {
    String t(String key) => AppStrings.text(context, key);
    final date = _cloudService.lastBackupAt;
    if (date == null) return t('cloud_backup_never');
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    String t(String key) => AppStrings.text(context, key);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _account != null
                    ? CircleAvatar(
                        radius: 20,
                        backgroundImage: _account!.photoUrl != null
                            ? NetworkImage(_account!.photoUrl!)
                            : null,
                        child: _account!.photoUrl == null
                            ? const Icon(Icons.cloud_done_outlined)
                            : null,
                      )
                    : const CircleAvatar(
                        radius: 20,
                        child: Icon(Icons.cloud_off_outlined),
                      ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('cloud_backup_title'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _account?.email ?? t('cloud_backup_not_connected'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _cloudService.isBusy
                      ? null
                      : (_account == null ? _signIn : _signOut),
                  child: Text(
                    _account == null ? t('connect') : t('disconnect'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t('cloud_backup_desc'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${t('cloud_backup_retention')}: ${_cloudService.backupRetentionCount}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '${t('cloud_backup_threshold')}: ${_cloudService.autoBackupThreshold}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '${t('cloud_backup_last_backup')}: ${_lastBackupLabel(context)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '${t('cloud_backup_pending_changes')}: ${_cloudService.pendingChanges}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: (_account != null && !_cloudService.isBusy)
                      ? _backupNow
                      : null,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(t('cloud_backup_now')),
                ),
                FilledButton.tonalIcon(
                  onPressed: (_account != null && !_cloudService.isBusy)
                      ? _restoreLatest
                      : null,
                  icon: const Icon(Icons.restore_rounded),
                  label: Text(t('cloud_restore_latest')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('cloud_auto_backup')),
              subtitle: Text(t('cloud_auto_backup_desc')),
              value: settings.cloudAutoBackupEnabled,
              onChanged: (value) {
                settings.setCloudAutoBackupEnabled(value);
              },
            ),
            const Divider(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('cloud_auto_restore')),
              subtitle: Text(t('cloud_auto_restore_desc')),
              value: settings.cloudAutoRestoreEnabled,
              onChanged: (value) {
                settings.setCloudAutoRestoreEnabled(value);
              },
            ),
          ],
        ),
      ),
    );
  }
}
