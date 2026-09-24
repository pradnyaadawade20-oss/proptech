import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const String supportEmail = 'support@proptech.app';

/// Keep in sync with `version:` in pubspec.yaml.
const String appVersion = '0.1.0';

/// Opens the user's email app with a pre-filled message to support.
/// If no email app is available, copies the address so it isn't lost.
Future<void> launchSupportEmail(
  BuildContext context, {
  String subject = 'PropTech support',
  String body = '',
}) async {
  final uri = Uri.parse(
    'mailto:$supportEmail?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
  );

  var launched = false;
  try {
    launched = await launchUrl(uri);
  } catch (_) {
    launched = false;
  }

  if (!launched && context.mounted) {
    await Clipboard.setData(const ClipboardData(text: supportEmail));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No email app found. Address copied: $supportEmail')),
    );
  }
}