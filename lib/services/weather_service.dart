import 'dart:convert';

import 'geo.dart';
import 'net.dart';

class HourForecast {
  final DateTime start;
  final int tempF;
  final double windMph;
  final String short;
  final int precipPct;
  final bool isDay;
  HourForecast(this.start, this.tempF, this.windMph, this.short, this.precipPct, this.isDay);
}

class WxAlert {
  final String event;
  final String headline;
  final DateTime? onset;
  final DateTime? ends;
  WxAlert(this.event, this.headline, this.onset, this.ends);
  bool get isFire => event.toLowerCase().contains('red flag') || event.toLowerCase().contains('fire weather');
}

class WeatherSnapshot {
  final String place;
  final List<HourForecast> hours;
  final List<WxAlert> alerts;
  WeatherSnapshot(this.place, this.hours, this.alerts);

  HourForecast? get now => hours.isEmpty ? null : hours.first;
  bool get redFlag => alerts.any((a) => a.isFire);

  HourForecast? at(DateTime t) {
    HourForecast? best;
    var bd = 1 << 30;
    for (final h in hours) {
      final d = h.start.difference(t).inMinutes.abs();
      if (d < bd) {
        bd = d;
        best = h;
      }
    }
    return bd <= 90 ? best : null;
  }

  bool fireAlertAt(DateTime t) => alerts.any((a) =>
      a.isFire &&
      (a.onset == null || !t.isBefore(a.onset!.subtract(const Duration(hours: 1)))) &&
      (a.ends == null || t.isBefore(a.ends!)));
}

/// National Weather Service (api.weather.gov): free, no key. US only.
class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();
  final Map<String, (DateTime, WeatherSnapshot)> _cache = {};

  Future<WeatherSnapshot> get(LL p) async {
    final key = '${p.lat.toStringAsFixed(2)},${p.lon.toStringAsFixed(2)}';
    final c = _cache[key];
    if (c != null && DateTime.now().difference(c.$1).inMinutes < 30) return c.$2;
    final pts = jsonDecode(await Net.get(Uri.parse('https://api.weather.gov/points/${p.lat.toStringAsFixed(4)},${p.lon.toStringAsFixed(4)}')))
        as Map<String, dynamic>;
    final props = pts['properties'] as Map<String, dynamic>;
    final rel = (props['relativeLocation'] as Map?)?['properties'] as Map?;
    final place = rel == null ? '' : '${rel['city']}, ${rel['state']}';
    final hourlyUrl = props['forecastHourly'] as String?;
    final hours = <HourForecast>[];
    if (hourlyUrl != null) {
      try {
        final fj = jsonDecode(await Net.get(Uri.parse(hourlyUrl), timeout: const Duration(seconds: 25))) as Map<String, dynamic>;
        for (final per in ((fj['properties'] as Map)['periods'] as List)) {
          final m = per as Map<String, dynamic>;
          final wind = RegExp(r'(\d+)').allMatches((m['windSpeed'] as String?) ?? '0').map((x) => int.parse(x.group(1)!)).toList();
          hours.add(HourForecast(
            DateTime.parse(m['startTime'] as String).toLocal(),
            (m['temperature'] as num).round(),
            wind.isEmpty ? 0 : wind.reduce((a, b) => a > b ? a : b).toDouble(),
            (m['shortForecast'] as String?) ?? '',
            ((m['probabilityOfPrecipitation'] as Map?)?['value'] as num?)?.round() ?? 0,
            m['isDaytime'] == true,
          ));
        }
      } catch (_) {}
    }
    final alerts = <WxAlert>[];
    try {
      final aj = jsonDecode(await Net.get(Uri.parse(
              'https://api.weather.gov/alerts/active?point=${p.lat.toStringAsFixed(4)},${p.lon.toStringAsFixed(4)}')))
          as Map<String, dynamic>;
      for (final f in (aj['features'] as List? ?? [])) {
        final pr = (f as Map)['properties'] as Map;
        alerts.add(WxAlert(
          (pr['event'] as String?) ?? 'Alert',
          (pr['headline'] as String?) ?? '',
          pr['onset'] == null ? null : DateTime.tryParse(pr['onset'] as String)?.toLocal(),
          (pr['ends'] ?? pr['expires']) == null ? null : DateTime.tryParse((pr['ends'] ?? pr['expires']) as String)?.toLocal(),
        ));
      }
    } catch (_) {}
    final snap = WeatherSnapshot(place, hours, alerts);
    _cache[key] = (DateTime.now(), snap);
    return snap;
  }
}

/// Open-Meteo elevation API (free, no key, 100 points per call).
class ElevationService {
  static Future<List<double>> profile(List<LL> line, {int samples = 80}) async {
    final pts = resample(line, samples);
    final out = <double>[];
    for (var i = 0; i < pts.length; i += 100) {
      final chunk = pts.sublist(i, (i + 100).clamp(0, pts.length));
      final uri = Uri.parse('https://api.open-meteo.com/v1/elevation').replace(queryParameters: {
        'latitude': chunk.map((p) => p.lat.toStringAsFixed(5)).join(','),
        'longitude': chunk.map((p) => p.lon.toStringAsFixed(5)).join(','),
      });
      final j = jsonDecode(await Net.get(uri)) as Map<String, dynamic>;
      out.addAll((j['elevation'] as List).map((e) => (e as num).toDouble()));
    }
    return out;
  }

  static List<LL> resample(List<LL> line, int n) {
    if (line.length < 2) return line;
    final total = Geo.lineLength(line);
    final step = total / (n - 1);
    final out = <LL>[line.first];
    var acc = 0.0;
    var target = step;
    for (var i = 0; i < line.length - 1; i++) {
      final a = line[i], b = line[i + 1];
      final seg = Geo.distance(a, b);
      while (acc + seg >= target && out.length < n - 1) {
        final t = seg == 0 ? 0.0 : (target - acc) / seg;
        out.add(LL(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t));
        target += step;
      }
      acc += seg;
    }
    out.add(line.last);
    return out;
  }

  static double gainMeters(List<double> elev) {
    var g = 0.0;
    for (var i = 1; i < elev.length; i++) {
      final d = elev[i] - elev[i - 1];
      if (d > 0) g += d;
    }
    return g;
  }

  /// Difficulty from distance and gain (AllTrails-style rough score).
  static String difficulty(double lengthM, double gainM) {
    final miles = lengthM / 1609.344;
    final gainFt = gainM * 3.28084;
    final score = miles + gainFt / 500.0;
    if (score < 4) return 'Easy';
    if (score < 9) return 'Moderate';
    return 'Hard';
  }
}
