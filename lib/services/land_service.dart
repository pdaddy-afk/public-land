import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'geo.dart';
import 'net.dart';

/// Shooting status categories used everywhere in the app.
enum ShootStatus { allowed, restricted, check, prohibited, unknown }

extension ShootStatusX on ShootStatus {
  String get label => switch (this) {
        ShootStatus.allowed => 'Allowed',
        ShootStatus.restricted => 'Restricted',
        ShootStatus.check => 'Check local rules',
        ShootStatus.prohibited => 'No shooting',
        ShootStatus.unknown => 'Not public land',
      };
  String get code => name;
  static ShootStatus parse(String? s) =>
      ShootStatus.values.firstWhere((e) => e.name == s, orElse: () => ShootStatus.unknown);
}

class ManagerInfo {
  final String code;
  final String name;
  final String color; // hex for Land mode
  final ShootStatus status;
  final String rules;
  final String source;
  const ManagerInfo(this.code, this.name, this.color, this.status, this.rules, this.source);
}

const _blmRules =
    'Target shooting is generally allowed on BLM land when done safely: not on or across roads, not in developed recreation sites, '
    'use a safe backstop, no exploding targets, and pack out all targets, brass and trash. State and county laws still apply.';
const _usfsRules =
    'Allowed unless restricted. 36 CFR 261.10(d): no shooting within 150 yards of a residence, building, campsite, developed '
    'recreation site or occupied area; not across or on a Forest road or body of water; not into or within a cave; never where any '
    'person or property is exposed to injury. Exploding targets are always prohibited.';
const _npsRules = 'National Park Service units prohibit target shooting (36 CFR 2.4). Hunting only where a park\'s law allows it.';
const _fwsRules =
    'National Wildlife Refuges generally prohibit target shooting; firearms may be used only for authorized hunting (50 CFR 27.42).';

const _srcBlm = 'https://www.blm.gov/programs/recreation/recreation-activities/recreational-shooting';
const _srcUsfs = 'https://www.ecfr.gov/current/title-36/chapter-II/part-261/subpart-A/section-261.10';
const _srcNps = 'https://www.ecfr.gov/current/title-36/chapter-I/part-2/section-2.4';
const _srcFws = 'https://www.ecfr.gov/current/title-50/chapter-I/subchapter-C/part-27/subpart-D/section-27.42';
const _srcPad = 'https://www.usgs.gov/programs/gap-analysis-project/science/pad-us-data-overview';

ManagerInfo managerInfo(String? code) {
  switch (code) {
    case 'BLM':
      return const ManagerInfo('BLM', 'Bureau of Land Management', '#E3C26A', ShootStatus.allowed, _blmRules, _srcBlm);
    case 'USFS':
      return const ManagerInfo('USFS', 'U.S. Forest Service', '#6FAE6F', ShootStatus.allowed, _usfsRules, _srcUsfs);
    case 'NPS':
      return const ManagerInfo('NPS', 'National Park Service', '#9C7BC4', ShootStatus.prohibited, _npsRules, _srcNps);
    case 'FWS':
      return const ManagerInfo('FWS', 'U.S. Fish & Wildlife Service', '#5FB3B3', ShootStatus.prohibited, _fwsRules, _srcFws);
    case 'DOD':
      return const ManagerInfo('DOD', 'Department of Defense', '#B06A6A', ShootStatus.prohibited,
          'Military land. No public target shooting.', _srcPad);
    case 'TRIB':
      return const ManagerInfo('TRIB', 'Tribal land', '#A88462', ShootStatus.prohibited,
          'Tribal land is not public land. Shooting requires the tribe\'s permission.', _srcPad);
    case 'USBR':
    case 'USACE':
    case 'TVA':
      return ManagerInfo(code!, code == 'USBR' ? 'Bureau of Reclamation' : code == 'USACE' ? 'Army Corps of Engineers' : 'Tennessee Valley Authority',
          '#7FA3C9', ShootStatus.check, 'Federal water project land. Shooting rules vary by project; check the local office.', _srcPad);
    case 'SFW':
      return const ManagerInfo('SFW', 'State Fish & Wildlife', '#6E9BD1', ShootStatus.check,
          'State wildlife areas usually allow hunting in season but often prohibit target shooting. Check the area\'s regulations.', _srcPad);
    case 'SPR':
      return const ManagerInfo('SPR', 'State Parks', '#6E9BD1', ShootStatus.prohibited,
          'State parks generally prohibit target shooting.', _srcPad);
    case 'SLB':
    case 'SDOL':
    case 'SDNR':
    case 'SDC':
    case 'OTHS':
      return ManagerInfo(code!, 'State land', '#6E9BD1', ShootStatus.check,
          'State trust or agency land. Access and shooting rules vary by state; check local rules.', _srcPad);
    case 'CITY':
    case 'CNTY':
    case 'REG':
    case 'RWD':
    case 'JNT':
      return ManagerInfo(code!, 'Local government land', '#8E9AA6', ShootStatus.prohibited,
          'City, county and district parks and open space generally prohibit shooting.', _srcPad);
    case 'NGO':
    case 'PVT':
      return ManagerInfo(code!, code == 'NGO' ? 'Nonprofit preserve' : 'Private conservation land', '#8E9AA6',
          ShootStatus.prohibited, 'Privately managed land. No shooting without the owner\'s permission.', _srcPad);
    default:
      return ManagerInfo(code ?? 'UNK', code == null ? 'Unknown' : 'Other ($code)', '#8E9AA6', ShootStatus.check,
          'Manager not recognized. Treat as off-limits until you confirm.', _srcPad);
  }
}

class Closure {
  final String id, name, kind, summary, source;
  final ShootStatus status;
  final String? manager, note;
  final bool approximate;
  final DateTime? effective, expires;
  final Map<String, dynamic>? geometry;
  Closure({
    required this.id,
    required this.name,
    required this.kind,
    required this.summary,
    required this.source,
    required this.status,
    this.manager,
    this.note,
    this.approximate = false,
    this.effective,
    this.expires,
    this.geometry,
  });

  bool activeOn(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    if (effective != null && day.isBefore(effective!)) return false;
    if (expires != null && day.isAfter(expires!)) return false;
    return true;
  }
}

class LandParcel {
  final String manager; // PAD-US Mang_Name code
  final String unit;
  final String designation;
  final String access;
  final Map<String, dynamic> geometry;
  ShootStatus status;
  LandParcel(this.manager, this.unit, this.designation, this.access, this.geometry, this.status);
  ManagerInfo get info => managerInfo(manager);
}

class LandStatus {
  final LL point;
  final LandParcel? parcel;
  final ShootStatus status;
  final List<Closure> closures;
  final bool inCuratedRegion;
  final bool expiredOrdersNearby;
  LandStatus(this.point, this.parcel, this.status, this.closures, this.inCuratedRegion, this.expiredOrdersNearby);

  ManagerInfo get info => managerInfo(parcel?.manager);
  String get unitName => parcel?.unit ?? 'Private or unmapped land';
  String get managerName => parcel == null ? 'Not in public land data' : info.name;
  String get sourceUrl => closures.isNotEmpty ? closures.first.source : (parcel == null ? _srcPad : info.source);

  /// "Check local orders" flag: everywhere outside the curated region, or when
  /// only expired/seasonal data is known.
  bool get checkLocalOrders => !inCuratedRegion || expiredOrdersNearby;

  String get rulesText {
    final b = StringBuffer();
    for (final c in closures) {
      b.writeln('• ${c.name}: ${c.summary}');
      if (c.note != null) b.writeln('  ${c.note}');
    }
    if (parcel != null) {
      b.writeln(info.rules);
    } else {
      b.writeln('This point is not in the PAD-US public land inventory. Assume it is private: no shooting without permission.');
    }
    if (!inCuratedRegion) {
      b.writeln('Check local orders: this app only has a curated closure list for Southern California. Look up the local field office or ranger district for fire restrictions and closures.');
    }
    return b.toString().trim();
  }
}

class LandService {
  LandService._();
  static final LandService instance = LandService._();

  static const padUrl =
      'https://services.arcgis.com/v01gqwM5QqNysAAi/arcgis/rest/services/Fee_Managers_PADUS/FeatureServer/0/query';

  List<Closure> _closures = [];
  List<Map<String, dynamic>> _unitRules = [];
  BBox? _region;
  Map<String, dynamic>? redFlagRule;
  bool _loaded = false;

  final Map<String, List<LandParcel>> _cache = {};
  List<LandParcel> lastParcels = [];
  BBox? lastBox;
  double? _lastZoom;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/closures_socal.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final r = j['region'] as Map<String, dynamic>;
    _region = BBox((r['s'] as num).toDouble(), (r['w'] as num).toDouble(), (r['n'] as num).toDouble(), (r['e'] as num).toDouble());
    redFlagRule = j['redFlagRule'] as Map<String, dynamic>?;
    _unitRules = (j['unitRules'] as List).cast<Map<String, dynamic>>();
    _closures = (j['features'] as List).map((f) {
      final p = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
      return Closure(
        id: p['id'] as String,
        name: p['name'] as String,
        kind: p['kind'] as String,
        summary: p['summary'] as String,
        source: p['source'] as String,
        status: ShootStatusX.parse(p['status'] as String?),
        manager: p['manager'] as String?,
        note: p['note'] as String?,
        approximate: p['approximate'] == true,
        effective: p['effective'] == null ? null : DateTime.parse(p['effective'] as String),
        expires: p['expires'] == null ? null : DateTime.parse(p['expires'] as String),
        geometry: f['geometry'] as Map<String, dynamic>,
      );
    }).toList();
    _loaded = true;
  }

  bool inCuratedRegion(LL p) => _region?.contains(p) ?? false;

  /// Site-specific closure polygons active today, as GeoJSON for the map.
  /// Seasonal area-wide orders are applied to parcel colours instead of drawn.
  Map<String, dynamic> activeClosureGeojson() {
    final now = DateTime.now();
    return {
      'type': 'FeatureCollection',
      'features': [
        for (final c in _closures)
          if (c.activeOn(now) && c.kind != 'seasonal')
            {
              'type': 'Feature',
              'properties': {'id': c.id, 'name': c.name},
              'geometry': c.geometry,
            }
      ]
    };
  }

  List<Map<String, dynamic>> get unitRules => _unitRules;

  /// Fetch PAD-US fee-manager polygons for a bounding box.
  static Object? _decode(String s) => jsonDecode(s);

  Future<List<LandParcel>> fetch(BBox box, double zoom) async {
    await ensureLoaded();
    final zb = zoom < 11 ? 10.0 : 13.0; // two detail levels only, so the cache hits
    zoom = zb;
    box = box.snap(zb < 11 ? 0.25 : 0.08);
    if (lastBox != null && _lastZoom == zb && lastBox!.containsBox(box)) return lastParcels;
    final tol = (Geo.metersPerPixel(zoom, box.center.lat) * 1.2) / 111320.0;
    final key = '${box.esriEnvelope}|${zoom.round()}';
    final hit = _cache[key];
    if (hit != null) return lastParcels = hit;
    final uri = Uri.parse(padUrl).replace(queryParameters: {
      'where': '1=1',
      'geometry': box.esriEnvelope,
      'geometryType': 'esriGeometryEnvelope',
      'inSR': '4326',
      'spatialRel': 'esriSpatialRelIntersects',
      'outFields': 'Mang_Name,Unit_Nm,Loc_Nm,Des_Tp,Pub_Access',
      'returnGeometry': 'true',
      'outSR': '4326',
      'maxAllowableOffset': tol.toStringAsFixed(6),
      'geometryPrecision': '5',
      'resultRecordCount': '2000',
      'f': 'geojson',
    });
    final res = await Net.get(uri, timeout: const Duration(seconds: 30));
    final j = (await compute(_decode, res)) as Map<String, dynamic>;
    final out = <LandParcel>[];
    for (final f in (j['features'] as List? ?? [])) {
      final m = f as Map<String, dynamic>;
      final p = (m['properties'] as Map?)?.cast<String, dynamic>() ?? {};
      final g = m['geometry'] as Map<String, dynamic>?;
      if (g == null) continue;
      final mgr = (p['Mang_Name'] as String?) ?? 'UNK';
      final unit = (p['Unit_Nm'] as String?) ?? (p['Loc_Nm'] as String?) ?? 'Unnamed unit';
      final parcel = LandParcel(mgr, unit, (p['Des_Tp'] as String?) ?? '', (p['Pub_Access'] as String?) ?? '', g,
          managerInfo(mgr).status);
      parcel.status = _parcelStatus(parcel);
      out.add(parcel);
    }
    if (_cache.length > 12) _cache.remove(_cache.keys.first);
    _cache[key] = out;
    lastParcels = out;
    lastBox = box;
    _lastZoom = zb;
    return out;
  }

  /// Unit-wide rules (e.g. forest-wide orders) that apply to a parcel.
  Map<String, dynamic>? _unitRuleFor(LandParcel p) {
    for (final r in _unitRules) {
      if (r['manager'] == p.manager && p.unit.toLowerCase().contains((r['match'] as String).toLowerCase())) {
        final exp = r['expires'] == null ? null : DateTime.tryParse(r['expires'] as String);
        if (exp != null && DateTime.now().isAfter(exp.add(const Duration(days: 1)))) continue;
        return r;
      }
    }
    return null;
  }

  ShootStatus _parcelStatus(LandParcel p) {
    final base = managerInfo(p.manager).status;
    if (base != ShootStatus.allowed) return base;
    if (p.access == 'XA') return ShootStatus.prohibited; // closed to public access
    if (_unitRuleFor(p) != null) return ShootStatus.restricted;
    return base;
  }

  /// Full status at a point using loaded parcels (or a point query if none loaded).
  Future<LandStatus> statusAt(LL pt) async {
    await ensureLoaded();
    LandParcel? parcel;
    for (final p in lastParcels) {
      if (Geo.geometryContains(p.geometry, pt)) {
        parcel = p;
        break;
      }
    }
    if (parcel == null && !(lastBox?.contains(pt) ?? false)) {
      try {
        final parcels = await fetch(BBox.around(pt, 1500), 14);
        for (final p in parcels) {
          if (Geo.geometryContains(p.geometry, pt)) {
            parcel = p;
            break;
          }
        }
      } catch (_) {}
    }
    return _evaluate(pt, parcel);
  }

  /// Synchronous status using only already-loaded parcels (no network).
  LandStatus statusAtLocal(LL pt) {
    LandParcel? parcel;
    for (final p in lastParcels) {
      if (Geo.geometryContains(p.geometry, pt)) {
        parcel = p;
        break;
      }
    }
    return _evaluate(pt, parcel);
  }

  LandStatus _evaluate(LL pt, LandParcel? parcel) {
    final now = DateTime.now();
    final closures = <Closure>[];
    var expiredNearby = false;
    if (parcel != null) {
      final ur = _unitRuleFor(parcel);
      if (ur != null) {
        closures.add(Closure(
          id: ur['id'] as String,
          name: parcel.unit,
          kind: 'unit',
          summary: ur['summary'] as String,
          source: ur['source'] as String,
          status: ShootStatusX.parse(ur['status'] as String?),
          manager: ur['manager'] as String?,
        ));
      }
    }
    for (final c in _closures) {
      if (!Geo.geometryContains(c.geometry, pt)) continue;
      // Seasonal / BLM orders only bind on that agency's land.
      if (c.manager != null && parcel != null && parcel.manager != c.manager) continue;
      if (parcel == null) continue;
      if (c.activeOn(now)) {
        closures.add(c);
      } else {
        expiredNearby = true;
      }
    }
    var status = parcel?.status ?? ShootStatus.unknown;
    if (closures.isNotEmpty && (status == ShootStatus.allowed || status == ShootStatus.restricted)) {
      status = ShootStatus.restricted;
    }
    return LandStatus(pt, parcel, status, closures, inCuratedRegion(pt), expiredNearby);
  }

  /// GeoJSON for the map with status + colour baked into properties.
  Map<String, dynamic> parcelsGeojson(List<LandParcel> parcels) {
    final now = DateTime.now();
    final active = _closures.where((c) => c.activeOn(now)).toList();
    return {
      'type': 'FeatureCollection',
      'features': [
        for (var i = 0; i < parcels.length; i++)
          {
            'type': 'Feature',
            'id': i,
            'properties': {
              'mgr': parcels[i].manager,
              'unit': parcels[i].unit,
              'status': _mapStatus(parcels[i], active).name,
              'color': parcels[i].info.color,
            },
            'geometry': parcels[i].geometry,
          }
      ]
    };
  }

  ShootStatus _mapStatus(LandParcel p, List<Closure> active) {
    if (p.status != ShootStatus.allowed) return p.status;
    final rep = _firstVertex(p.geometry);
    if (rep == null) return p.status;
    for (final c in active) {
      if (c.kind == 'seasonal' && c.manager == p.manager && Geo.geometryContains(c.geometry, rep)) {
        return ShootStatus.restricted;
      }
    }
    return p.status;
  }

  LL? _firstVertex(Map<String, dynamic> g) {
    try {
      final coords = g['coordinates'] as List;
      final ring = (g['type'] == 'Polygon' ? coords.first : (coords.first as List).first) as List;
      final v = ring.first as List;
      return LL((v[1] as num).toDouble(), (v[0] as num).toDouble());
    } catch (_) {
      return null;
    }
  }

  /// Public land units near a point for the Explore list.
  Future<List<NearbyUnit>> nearby(LL c, {double radiusM = 60000}) async {
    await ensureLoaded();
    final box = BBox.around(c, radiusM);
    final uri = Uri.parse(padUrl).replace(queryParameters: {
      'where': "Mang_Name IN ('BLM','USFS','SFW','USBR','USACE','SLB','SDOL')",
      'geometry': box.esriEnvelope,
      'geometryType': 'esriGeometryEnvelope',
      'inSR': '4326',
      'spatialRel': 'esriSpatialRelIntersects',
      'outFields': 'Mang_Name,Unit_Nm,Loc_Nm,Des_Tp,Pub_Access',
      'returnGeometry': 'true',
      'outSR': '4326',
      'maxAllowableOffset': '0.01',
      'geometryPrecision': '3',
      'resultRecordCount': '400',
      'f': 'geojson',
    });
    final res = await Net.get(uri, timeout: const Duration(seconds: 30));
    final j = jsonDecode(res) as Map<String, dynamic>;
    final best = <String, NearbyUnit>{};
    for (final f in (j['features'] as List? ?? [])) {
      final m = f as Map<String, dynamic>;
      final p = (m['properties'] as Map?)?.cast<String, dynamic>() ?? {};
      final g = m['geometry'] as Map<String, dynamic>?;
      if (g == null) continue;
      final mgr = (p['Mang_Name'] as String?) ?? 'UNK';
      final unit = (p['Unit_Nm'] as String?) ?? (p['Loc_Nm'] as String?) ?? 'Unnamed';
      final parcel = LandParcel(mgr, unit, (p['Des_Tp'] as String?) ?? '', (p['Pub_Access'] as String?) ?? '', g,
          managerInfo(mgr).status);
      parcel.status = _parcelStatus(parcel);
      final near = _nearestVertex(g, c);
      final d = Geo.geometryContains(g, c) ? 0.0 : Geo.distance(c, near);
      // Check closures at the nearest vertex for an honest status.
      final st = _evaluate(near, parcel);
      final key = '$mgr|$unit';
      final prev = best[key];
      if (prev == null || d < prev.distanceM) {
        best[key] = NearbyUnit(unit, mgr, st.status, d, near, st.checkLocalOrders);
      }
    }
    // BLM and National Forest first (where shooting is generally allowed), then the rest.
    int rank(NearbyUnit u) => (u.manager == 'BLM' || u.manager == 'USFS') ? 0 : 1;
    final list = best.values.toList()
      ..sort((a, b) {
        final r = rank(a) - rank(b);
        return r != 0 ? r : a.distanceM.compareTo(b.distanceM);
      });
    return list.take(8).toList();
  }

  LL _nearestVertex(Map<String, dynamic> g, LL c) {
    LL best = c;
    var bd = double.infinity;
    void scan(List ring) {
      for (final v in ring) {
        final p = LL(((v as List)[1] as num).toDouble(), (v[0] as num).toDouble());
        final d = Geo.distance(c, p);
        if (d < bd) {
          bd = d;
          best = p;
        }
      }
    }

    if (g['type'] == 'Polygon') {
      for (final r in g['coordinates'] as List) {
        scan(r as List);
      }
    } else if (g['type'] == 'MultiPolygon') {
      for (final poly in g['coordinates'] as List) {
        for (final r in poly as List) {
          scan(r as List);
        }
      }
    }
    return best;
  }

  /// Persistable snapshot for offline use.
  String exportCache() => jsonEncode({
        'box': lastBox?.toJson(),
        'parcels': [
          for (final p in lastParcels) {'m': p.manager, 'u': p.unit, 'd': p.designation, 'a': p.access, 'g': p.geometry}
        ]
      });

  Future<void> importCache(String raw) async {
    await ensureLoaded();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['box'] == null) return;
    lastBox = BBox.fromJson((j['box'] as Map).cast<String, dynamic>());
    lastParcels = [
      for (final p in (j['parcels'] as List))
        () {
          final m = (p as Map).cast<String, dynamic>();
          final parcel = LandParcel(m['m'] as String, m['u'] as String, m['d'] as String, m['a'] as String,
              (m['g'] as Map).cast<String, dynamic>(), managerInfo(m['m'] as String).status);
          parcel.status = _parcelStatus(parcel);
          return parcel;
        }()
    ];
  }

  static http.Client get client => Net.client;
}

class NearbyUnit {
  final String unit;
  final String manager;
  final ShootStatus status;
  final double distanceM;
  final LL nearest;
  final bool checkLocal;
  NearbyUnit(this.unit, this.manager, this.status, this.distanceM, this.nearest, this.checkLocal);
}
