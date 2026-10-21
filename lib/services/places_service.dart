import 'dart:convert';

import 'geo.dart';
import 'net.dart';

class Place {
  final String name;
  final String detail;
  final LL p;
  Place(this.name, this.detail, this.p);
}

/// Photon (komoot) geocoder: free, keyless, built on OSM. Used with a debounce
/// and a minimum query length to respect its fair-use policy.
class PlacesService {
  static Future<List<Place>> search(String q, {LL? bias}) async {
    if (q.trim().length < 3) return [];
    final uri = Uri.parse('https://photon.komoot.io/api/').replace(queryParameters: {
      'q': q,
      'limit': '8',
      'lang': 'en',
      if (bias != null) 'lat': bias.lat.toStringAsFixed(3),
      if (bias != null) 'lon': bias.lon.toStringAsFixed(3),
    });
    final j = jsonDecode(await Net.get(uri)) as Map<String, dynamic>;
    final out = <Place>[];
    for (final f in (j['features'] as List? ?? [])) {
      final m = f as Map<String, dynamic>;
      final pr = (m['properties'] as Map).cast<String, dynamic>();
      final c = (m['geometry'] as Map)['coordinates'] as List;
      if (pr['countrycode'] != null && pr['countrycode'] != 'US') continue;
      final detail = [pr['city'], pr['county'], pr['state']].whereType<String>().join(', ');
      out.add(Place((pr['name'] as String?) ?? detail, detail, LL((c[1] as num).toDouble(), (c[0] as num).toDouble())));
    }
    return out;
  }

  static Future<String?> reverse(LL p) async {
    try {
      final uri = Uri.parse('https://photon.komoot.io/reverse').replace(queryParameters: {
        'lat': p.lat.toStringAsFixed(4),
        'lon': p.lon.toStringAsFixed(4),
        'limit': '1',
      });
      final j = jsonDecode(await Net.get(uri)) as Map<String, dynamic>;
      final f = (j['features'] as List).first as Map;
      final pr = (f['properties'] as Map).cast<String, dynamic>();
      final city = (pr['city'] ?? pr['town'] ?? pr['village'] ?? pr['county']) as String?;
      final st = pr['state'] as String?;
      if (city == null) return st;
      return st == null ? city : '$city, ${_abbr(st)}';
    } catch (_) {
      return null;
    }
  }

  static String _abbr(String s) => const {
        'California': 'CA', 'Arizona': 'AZ', 'Nevada': 'NV', 'Oregon': 'OR', 'Utah': 'UT', 'Colorado': 'CO',
        'New Mexico': 'NM', 'Idaho': 'ID', 'Montana': 'MT', 'Wyoming': 'WY', 'Washington': 'WA', 'Texas': 'TX',
      }[s] ??
      s;
}

/// OSRM public demo router for drive time (free, fair use). Falls back to an estimate.
class RoutingService {
  static Future<({double meters, Duration time, bool estimated})> drive(LL from, LL to) async {
    try {
      final uri = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/${from.lon},${from.lat};${to.lon},${to.lat}?overview=false');
      final j = jsonDecode(await Net.get(uri, timeout: const Duration(seconds: 12))) as Map<String, dynamic>;
      final r = (j['routes'] as List).first as Map;
      return (
        meters: (r['distance'] as num).toDouble(),
        time: Duration(seconds: (r['duration'] as num).round()),
        estimated: false
      );
    } catch (_) {
      final d = Geo.distance(from, to) * 1.35;
      return (meters: d, time: Duration(seconds: (d / 17.0).round()), estimated: true);
    }
  }
}
