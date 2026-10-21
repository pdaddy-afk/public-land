import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'geo.dart';

/// Free navigation hand-off: Google Maps, Apple Maps, or the Android geo: intent.
class Handoff {
  static Future<bool> googleMaps(LL p) => _open(Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}&travelmode=driving'));

  static Future<bool> appleMaps(LL p) =>
      _open(Uri.parse('https://maps.apple.com/?daddr=${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}&dirflg=d'));

  static Future<bool> geoIntent(LL p, String label) => _open(Uri.parse(
      'geo:${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}?q=${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}(${Uri.encodeComponent(label)})'));

  static Future<bool> url(String u) => _open(Uri.parse(u));

  static Future<bool> _open(Uri u) async {
    try {
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isIOSWeb => kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}

class ShareHelper {
  /// Share text through the system share sheet (Web Share API on iPhone Safari).
  /// Falls back to the clipboard and returns false when sharing is unavailable.
  static Future<bool> text(String text, {String? subject}) async {
    try {
      final r = await SharePlus.instance.share(ShareParams(text: text, subject: subject));
      if (r.status == ShareResultStatus.unavailable) throw Exception('unavailable');
      return true;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      return false;
    }
  }

  /// Share/download a calendar invite.
  static Future<void> ics(String ics, String fileName) async {
    final bytes = Uint8List.fromList(utf8.encode(ics));
    try {
      final r = await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'text/calendar', name: fileName)],
        fileNameOverrides: [fileName],
        subject: fileName,
      ));
      if (r.status == ShareResultStatus.unavailable) throw Exception('unavailable');
    } catch (_) {
      // Browser fallback: a data: URL opens the calendar import on iOS / downloads elsewhere.
      await launchUrl(Uri.parse('data:text/calendar;charset=utf-8,${Uri.encodeComponent(ics)}'));
    }
  }
}
