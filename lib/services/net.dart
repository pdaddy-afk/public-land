import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Small HTTP helper. Browsers forbid setting User-Agent, so it is only sent
/// from the Android app; NWS and Nominatim-style policies accept that.
class Net {
  static final http.Client client = http.Client();
  static const userAgent = 'PublicLandApp/1.0 (+https://github.com/pdaddy-afk/public-land)';

  static Map<String, String> headers([Map<String, String>? extra]) => {
        if (!kIsWeb) 'User-Agent': userAgent,
        'Accept': 'application/json, application/geo+json;q=0.9, */*;q=0.5',
        ...?extra,
      };

  static Future<String> get(Uri uri, {Duration timeout = const Duration(seconds: 20), Map<String, String>? extra}) async {
    final res = await client.get(uri, headers: headers(extra)).timeout(timeout);
    if (res.statusCode >= 400) {
      throw HttpError(res.statusCode, uri.host);
    }
    return res.body;
  }

  static Future<String> post(Uri uri, Object body,
      {Duration timeout = const Duration(seconds: 30), Map<String, String>? extra}) async {
    final res = await client.post(uri, headers: headers(extra), body: body).timeout(timeout);
    if (res.statusCode >= 400) {
      throw HttpError(res.statusCode, uri.host, res.body);
    }
    return res.body;
  }
}

class HttpError implements Exception {
  final int code;
  final String host;
  final String? body;
  HttpError(this.code, this.host, [this.body]);
  @override
  String toString() => 'HTTP $code from $host';
}
