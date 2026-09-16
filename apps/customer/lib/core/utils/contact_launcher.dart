import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'phone_utils.dart';

/// Opens the device Phone dialer and default Messages app only.
abstract final class ContactLauncher {
  static const _channel = MethodChannel('pasakay/contact');

  static Future<bool> openCall(String mobile) async {
    final number = PhoneUtils.toE164(mobile);
    if (number.isEmpty) return false;

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final ok = await _channel.invokeMethod<bool>('dial', {
          'number': number,
        });
        return ok ?? true;
      } catch (_) {
        // Fall through to url_launcher.
      }
    }

    try {
      return await launchUrl(
        Uri.parse('tel:$number'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openSms(String mobile, {String? body}) async {
    final number = PhoneUtils.toE164(mobile);
    if (number.isEmpty) return false;

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final ok = await _channel.invokeMethod<bool>('sms', {
          'number': number,
          if (body != null && body.isNotEmpty) 'body': body,
        });
        return ok ?? true;
      } catch (_) {
        // Fall through to url_launcher.
      }
    }

    try {
      final uri = body == null || body.isEmpty
          ? Uri.parse('sms:$number')
          : Uri.parse('sms:$number?body=${Uri.encodeComponent(body)}');
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
