import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../l10n/app_language.dart';
import '../ui/studio_components.dart';
import 'update_service.dart';

class AppUpdater {
  static const channel = MethodChannel('mosaic/update');
  static bool _checking = false;
  static Future<InstalledApp> installed() async => InstalledApp.fromJson(
    (await channel.invokeMapMethod<Object?, Object?>('info'))!,
  );
  static Future<void> check(
    BuildContext context, {
    bool automatic = false,
    bool Function()? canShow,
  }) async {
    if (_checking || !Platform.isAndroid) return;
    _checking = true;
    UpdateClient? client;
    try {
      final app = await installed();
      if (!app.release) {
        if (!automatic && context.mounted) {
          await _notice(context, tr('updateReleaseOnly'));
        }
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt('update_last_check') ?? 0;
      if (automatic &&
          now - last < const Duration(hours: 24).inMilliseconds &&
          now >= last) {
        return;
      }
      await prefs.setInt('update_last_check', now);
      client = UpdateClient(GithubTransport());
      final update = await client.check(app);
      client.close();
      client = null;
      if (!context.mounted || (canShow != null && !canShow())) return;
      if (update == null) {
        if (!automatic) {
          await _notice(context, tr('updateCurrent', [app.version]));
        }
      } else {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => UpdateDialog(installed: app, update: update),
        );
      }
    } catch (_) {
      if (!automatic && context.mounted) {
        await _notice(context, tr('updateCheckFailed'));
      }
    } finally {
      client?.close();
      _checking = false;
    }
  }

  static Future<void> _notice(BuildContext context, String text) =>
      showDialog<void>(
        context: context,
        builder: (context) => ShadDialog(
          title: Text(tr('checkForUpdates')),
          actions: [
            StudioButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('updateClose')),
            ),
          ],
          child: Text(text),
        ),
      );
}

class UpdateCheckButton extends StatefulWidget {
  const UpdateCheckButton({super.key});
  @override
  State<UpdateCheckButton> createState() => _UpdateCheckButtonState();
}

class _UpdateCheckButtonState extends State<UpdateCheckButton> {
  bool checking = false;
  @override
  Widget build(BuildContext context) => StudioButton(
    outline: true,
    onPressed: checking
        ? null
        : () async {
            setState(() => checking = true);
            await AppUpdater.check(context);
            if (mounted) setState(() => checking = false);
          },
    icon: const Icon(Icons.system_update),
    child: Text(tr(checking ? 'updateChecking' : 'checkForUpdates')),
  );
}

class UpdateDialog extends StatefulWidget {
  final InstalledApp installed;
  final AvailableUpdate update;
  final UpdateClient Function()? clientFactory;
  const UpdateDialog({
    super.key,
    required this.installed,
    required this.update,
    this.clientFactory,
  });
  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  UpdateClient? client;
  File? apk;
  int received = 0;
  bool downloading = false, installing = false, permissionNeeded = false;
  String? error;
  @override
  void dispose() {
    client?.cancel();
    super.dispose();
  }

  Future<void> download() async {
    setState(() {
      downloading = true;
      error = null;
      received = 0;
    });
    client = widget.clientFactory?.call() ?? UpdateClient(GithubTransport());
    try {
      final file = await client!.download(
        widget.update,
        Directory(widget.installed.directory),
        (bytes, _) {
          if (mounted) setState(() => received = bytes);
        },
      );
      if (mounted) setState(() => apk = file);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = tr(e is UpdateFailure ? e.key : 'updateDownloadFailed'),
        );
      }
    } finally {
      client?.close();
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> install() async {
    setState(() {
      installing = true;
      error = null;
    });
    try {
      final result = await AppUpdater.channel.invokeMethod<String>('install', {
        'path': apk!.path,
        'sha256': widget.update.hash,
        'code': widget.update.code,
      });
      if (mounted) setState(() => permissionNeeded = result == 'permission');
    } catch (_) {
      if (mounted) {
        setState(() {
          apk = null;
          permissionNeeded = false;
          error = tr('updateInstallFailed');
        });
      }
    } finally {
      if (mounted) setState(() => installing = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !downloading && !installing,
    child: ShadDialog(
      title: Text(tr('updateAvailable')),
      actions: [
        StudioButton(
          ghost: true,
          onPressed: installing
              ? null
              : () {
                  client?.cancel();
                  Navigator.pop(context);
                },
          child: Text(tr(downloading ? 'cancel2' : 'updateLater')),
        ),
        StudioButton(
          onPressed: downloading || installing
              ? null
              : apk == null
              ? download
              : install,
          icon: Icon(
            apk == null ? Icons.download_outlined : Icons.system_update,
          ),
          child: Text(tr(apk == null ? 'updateDownload' : 'updateInstall')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('updateVersions', [
              widget.installed.version,
              widget.update.version,
            ]),
          ),
          const SizedBox(height: 8),
          Text(
            tr('updateSize', [
              (widget.update.size / (1024 * 1024)).toStringAsFixed(1),
            ]),
          ),
          if (widget.update.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(child: Text(widget.update.notes)),
            ),
          ],
          if (downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: received / widget.update.size),
            const SizedBox(height: 8),
            Text('${(received / widget.update.size * 100).floor()}%'),
          ],
          if (apk != null) ...[
            const SizedBox(height: 12),
            Text(tr('updateVerified')),
          ],
          if (permissionNeeded) ...[
            const SizedBox(height: 12),
            Text(tr('updatePermissionHint')),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
  );
}
