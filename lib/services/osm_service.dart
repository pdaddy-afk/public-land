import 'dart:async';
import 'package:flutter/foundation.dart' show compute;
import 'dart:convert';

import 'geo.dart';
import 'net.dart';

/// An OSM way with geometry.
class OsmWay {
  final int id;
  final String highway;
  final String? name;
  final String? surface;
  final List<LL> geom;
  OsmWay(this.id, this.highway, this.name, this.surface, this.geom);

  bool get isTrail => const {'path', 'footway', 'bridleway', 'steps'}.contains(highway);
  bool get isTrack => highway == 'track';
  bool get isRoad => !isTrail; // tracks count as roads for shooting buffers

  Map<String, dynamic> toJson() => {
        'i': id,
        'h': highway,
        if (name != null) 'n': name,
        if (surface != null) 's': surface,
        'g': [for (final p in geom) [p.lon, p.lat]],
      };
  factory OsmWay.fromJson(Map<String, dynamic> j) => OsmWay(
        j['i'] as int,
        j['h'] as String,
        j['n'] as String?,
        j['s'] as String?,
        [for (final c in j['g'] as List) LL(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble())],
      );
}

class Poi {
  final LL p;
  final String kind; // building | camp | developed
  final String? name;
  Poi(this.p, this.kind, this.name);
}

class Hazards {
  final BBox box;
  final List<OsmWay> ways;
  final List<Poi> pois;
  Hazards(this.box, this.ways, this.pois);

  List<OsmWay> get trails => ways.where((w) => w.isTrail || w.isTrack).toList();
  List<OsmWay> get footTrails => ways.where((w) => w.isTrail).toList();
  List<OsmWay> get roads => ways.where((w) => w.isRoad).toList();

  double nearestTrail(LL p) => _nearest(p, footTrails);
  double nearestRoad(LL p) => _nearest(p, roads);
  double nearestStructure(LL p) {
    var best = double.infinity;
    for (final poi in pois) {
      final d = Geo.distance(p, poi.p);
      if (d < best) best = d;
    }
    return best;
  }

  double _nearest(LL p, List<OsmWay> ws) {
    var best = double.infinity;
    for (final w in ws) {
      final d = Geo.pointToLine(p, w.geom);
      if (d < best) best = d;
    }
    return best;
  }

  /// GeoJSON of every highway (buffer lines) for the map.
  Map<String, dynamic> linesGeojson() => {
        'type': 'FeatureCollection',
        'features': [
          for (final w in ways)
            {
              'type': 'Feature',
              'id': w.id,
              'properties': {'hw': w.highway, 'name': w.name ?? '', 'trail': w.isTrail || w.isTrack ? 1 : 0, 'wid': w.id},
              'geometry': {
                'type': 'LineString',
                'coordinates': [for (final p in w.geom) [p.lon, p.lat]]
              }
            }
        ]
      };

  Map<String, dynamic> poisGeojson() => {
        'type': 'FeatureCollection',
        'features': [
          for (final p in pois)
            {
              'type': 'Feature',
              'properties': {'kind': p.kind, 'name': p.name ?? ''},
              'geometry': {'type': 'Point', 'coordinates': [p.p.lon, p.p.lat]}
            }
        ]
      };

  /// Sample hazard points within [radius] meters (for the safe-direction cone).
  List<LL> hazardPointsNear(LL c, double radius) {
    final out = <LL>[];
    for (final w in ways) {
      for (var i = 0; i < w.geom.length; i++) {
        final p = w.geom[i];
        if (Geo.distance(c, p) <= radius) out.add(p);
        if (i < w.geom.length - 1) {
          // densify long segments
          final seg = Geo.distance(p, w.geom[i + 1]);
          if (seg > 60) {
            final n = (seg / 50).floor();
            for (var k = 1; k < n; k++) {
              final t = k / n;
              final q = LL(p.lat + (w.geom[i + 1].lat - p.lat) * t, p.lon + (w.geom[i + 1].lon - p.lon) * t);
              if (Geo.distance(c, q) <= radius) out.add(q);
            }
          }
        }
      }
    }
    for (final poi in pois) {
      if (Geo.distance(c, poi.p) <= radius) out.add(poi.p);
    }
    return out;
  }

  String toCache() => jsonEncode({
        'box': box.toJson(),
        'ways': [for (final w in ways) w.toJson()],
        'pois': [for (final p in pois) {'la': p.p.lat, 'lo': p.p.lon, 'k': p.kind, if (p.name != null) 'n': p.name}],
      });

  static Hazards fromCache(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return Hazards(
      BBox.fromJson((j['box'] as Map).cast<String, dynamic>()),
      [for (final w in j['ways'] as List) OsmWay.fromJson((w as Map).cast<String, dynamic>())],
      [
        for (final p in j['pois'] as List)
          Poi(LL(((p as Map)['la'] as num).toDouble(), (p['lo'] as num).toDouble()), p['k'] as String, p['n'] as String?)
      ],
    );
  }
}

/// A trail = one or more OSM ways sharing a name, chained in order.
class Trail {
  final String id;
  final String name;
  final String kind; // path | track | ...
  final List<LL> line;
  final List<int> wayIds;
  Trail(this.id, this.name, this.kind, this.line, this.wayIds);

  double get lengthM => Geo.lineLength(line);
  LL get trailhead => line.first;
  LL get midpoint => line[line.length ~/ 2];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'w': wayIds,
        'g': [for (final p in line) [p.lon, p.lat]],
      };
  factory Trail.fromJson(Map<String, dynamic> j) => Trail(
        j['id'] as String,
        j['name'] as String,
        j['kind'] as String,
        [for (final c in j['g'] as List) LL(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble())],
        (j['w'] as List).cast<int>(),
      );
}

class OsmService {
  OsmService._();
  static final OsmService instance = OsmService._();

  /// Public Overpass instances, tried in order (all free, fair-use).
  static const mirrors = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  Hazards? last;
  final Map<String, Hazards> _cache = {};

  Future<Hazards> fetch(BBox box) async {
    if (last != null && last!.box.containsBox(box)) return last!;
    final key = box.overpass;
    if (_cache[key] != null) return last = _cache[key]!;
    final b = box.overpass;
    final q = '[out:json][timeout:25];'
        '(way["highway"]($b););out geom qt;'
        '(way["building"]($b);node["building"]($b);'
        'nwr["tourism"~"^(camp_site|picnic_site|caravan_site|alpine_hut|wilderness_hut)\$"]($b);'
        'nwr["amenity"~"^(shelter|toilets|ranger_station)\$"]($b);'
        'nwr["leisure"~"^(park|playground|picnic_table)\$"]["name"]($b););out center qt;';
    // Ask every mirror at once and keep the first good answer.
    final done = Completer<String>();
    var failed = 0;
    Object? lastErr;
    for (final m in mirrors) {
      Net.post(Uri.parse(m), {'data': q}, timeout: const Duration(seconds: 25)).then((body) {
        if (!done.isCompleted && body.trimLeft().startsWith('{')) {
          done.complete(body);
        } else if (++failed == mirrors.length && !done.isCompleted) {
          done.completeError(Exception('OpenStreetMap (Overpass) is busy'));
        }
      }, onError: (e) {
        lastErr = e;
        if (++failed == mirrors.length && !done.isCompleted) {
          done.completeError(Exception('OpenStreetMap (Overpass) is busy: $lastErr'));
        }
      });
    }
    final body = await done.future;
    final h = await compute(OsmService._parseRec, (box, body));
    if (_cache.length > 8) _cache.remove(_cache.keys.first);
    _cache[key] = h;
    return last = h;
  }

  static Hazards _parseRec((BBox, String) a) => _parse(a.$1, a.$2);

  static Hazards _parse(BBox box, String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final ways = <OsmWay>[];
    final pois = <Poi>[];
    for (final e in (j['elements'] as List? ?? [])) {
      final m = e as Map<String, dynamic>;
      final tags = (m['tags'] as Map?)?.cast<String, dynamic>() ?? {};
      if (m['type'] == 'way' && tags['highway'] != null && m['geometry'] != null) {
        final g = [
          for (final c in m['geometry'] as List)
            LL(((c as Map)['lat'] as num).toDouble(), (c['lon'] as num).toDouble())
        ];
        if (g.length < 2) continue;
        ways.add(OsmWay(m['id'] as int, tags['highway'] as String, tags['name'] as String?, tags['surface'] as String?, g));
        continue;
      }
      LL? p;
      if (m['lat'] != null) {
        p = LL((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble());
      } else if (m['center'] != null) {
        final c = m['center'] as Map;
        p = LL((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble());
      }
      if (p == null) continue;
      final kind = tags['building'] != null
          ? 'building'
          : (tags['tourism'] != null ? 'camp' : 'developed');
      pois.add(Poi(p, kind, tags['name'] as String?));
    }
    return Hazards(box, ways, pois);
  }

  /// Group trail-like ways into named trails.
  List<Trail> trails(Hazards h, {bool includeTracks = true}) {
    final groups = <String, List<OsmWay>>{};
    for (final w in h.ways) {
      if (!(w.isTrail || (includeTracks && w.isTrack))) continue;
      final key = w.name != null && w.name!.trim().isNotEmpty ? 'n:${w.name}' : 'w:${w.id}';
      groups.putIfAbsent(key, () => []).add(w);
    }
    final out = <Trail>[];
    groups.forEach((key, ws) {
      final line = _chain(ws);
      if (Geo.lineLength(line) < 200) return;
      final named = key.startsWith('n:');
      final w0 = ws.first;
      final name = named
          ? w0.name!
          : (w0.isTrack ? 'Unnamed dirt track' : 'Unnamed ${w0.highway}');
      out.add(Trail(key, name, w0.highway, line, ws.map((w) => w.id).toList()));
    });
    out.sort((a, b) {
      final an = a.id.startsWith('n:') ? 0 : 1, bn = b.id.startsWith('n:') ? 0 : 1;
      if (an != bn) return an - bn;
      return b.lengthM.compareTo(a.lengthM);
    });
    return out;
  }

  /// Greedy endpoint chaining so the elevation profile follows the trail.
  static List<LL> _chain(List<OsmWay> ways) {
    final rest = ways.map((w) => List<LL>.from(w.geom)).toList();
    rest.sort((a, b) => Geo.lineLength(b).compareTo(Geo.lineLength(a)));
    final line = rest.removeAt(0);
    while (rest.isNotEmpty) {
      var bestI = -1;
      var bestD = double.infinity;
      var mode = 0;
      for (var i = 0; i < rest.length; i++) {
        final r = rest[i];
        final cands = [
          Geo.distance(line.last, r.first),
          Geo.distance(line.last, r.last),
          Geo.distance(line.first, r.last),
          Geo.distance(line.first, r.first),
        ];
        for (var k = 0; k < 4; k++) {
          if (cands[k] < bestD) {
            bestD = cands[k];
            bestI = i;
            mode = k;
          }
        }
      }
      if (bestD > 400) break; // disconnected piece, stop
      final r = rest.removeAt(bestI);
      switch (mode) {
        case 0:
          line.addAll(r.skip(1));
        case 1:
          line.addAll(r.reversed.skip(1));
        case 2:
          line.insertAll(0, r.take(r.length - 1));
        default:
          line.insertAll(0, r.reversed.take(r.length - 1));
      }
    }
    return line;
  }
}
