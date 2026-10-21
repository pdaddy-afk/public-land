import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'geo.dart';
import 'land_service.dart';
import 'osm_service.dart';

/// 36 CFR 261.10(d) style buffer: 150 yards.
const bufferMeters = 137.16;

class Clearance {
  final LL p;
  final LandStatus land;
  final double trailM, roadM, structM;
  final bool hazardsLoaded;
  Clearance(this.p, this.land, this.trailM, this.roadM, this.structM, this.hazardsLoaded);

  bool get inBuffer => trailM < bufferMeters || roadM < bufferMeters || structM < bufferMeters;
  bool get clear => land.status == ShootStatus.allowed && hazardsLoaded && !inBuffer;

  String get headline => clear ? "You're clear to shoot" : 'Not clear to shoot';

  List<String> get reasons {
    final r = <String>[];
    switch (land.status) {
      case ShootStatus.allowed:
        break;
      case ShootStatus.restricted:
        r.add(land.closures.isNotEmpty ? 'Closure: ${land.closures.first.name}' : 'Restricted by local order');
      case ShootStatus.prohibited:
        r.add('${land.managerName}: no shooting');
      case ShootStatus.check:
        r.add('${land.managerName}: check local rules first');
      case ShootStatus.unknown:
        r.add('Not public land (assume private)');
    }
    if (!hazardsLoaded) r.add('Road and trail data not loaded');
    if (roadM < bufferMeters) r.add('Within 150 yd of a road (${Geo.fmtDist(roadM)})');
    if (trailM < bufferMeters) r.add('Within 150 yd of a trail (${Geo.fmtDist(trailM)})');
    if (structM < bufferMeters) r.add('Within 150 yd of a building or campsite (${Geo.fmtDist(structM)})');
    return r;
  }

  String get subline {
    final parts = <String>[land.parcel == null ? 'Not public land' : '${land.info.code} land'];
    if (hazardsLoaded) parts.add('${Geo.fmtDist(trailM)} from nearest trail');
    return parts.join(' · ');
  }
}

class ClearanceService {
  /// Offline/synchronous check with whatever is loaded.
  static Clearance evaluateLocal(LL p, Hazards? h) {
    final land = LandService.instance.statusAtLocal(p);
    if (h == null || !h.box.contains(p)) {
      return Clearance(p, land, double.infinity, double.infinity, double.infinity, false);
    }
    return Clearance(p, land, h.nearestTrail(p), h.nearestRoad(p), h.nearestStructure(p), true);
  }

  static Future<Clearance> evaluate(LL p) async {
    final land = await LandService.instance.statusAt(p);
    Hazards? h = OsmService.instance.last;
    if (h == null || !h.box.contains(p) || !_innerContains(h.box, p)) {
      try {
        h = await OsmService.instance.fetch(BBox.around(p, 1500));
      } catch (_) {
        h = (h != null && h.box.contains(p)) ? h : null;
      }
    }
    if (h == null) {
      return Clearance(p, land, double.infinity, double.infinity, double.infinity, false);
    }
    return Clearance(p, land, h.nearestTrail(p), h.nearestRoad(p), h.nearestStructure(p), true);
  }

  /// A point near the edge of a loaded box may have hazards just outside it.
  static bool _innerContains(BBox b, LL p) {
    final m = bufferMeters * 2;
    final inner = BBox(b.south + m / 110574, b.west + m / 92000, b.north - m / 110574, b.east - m / 92000);
    return inner.contains(p);
  }
}

/// Safe-direction cone: the widest open sector with no mapped roads, trails
/// or structures within [radius]. Returns null when nothing is mapped nearby.
class SafeCone {
  final double centerDeg;
  final double widthDeg;
  final int hazardCount;
  SafeCone(this.centerDeg, this.widthDeg, this.hazardCount);

  static SafeCone? compute(LL me, Hazards? h, {double radius = 900}) {
    if (h == null) return null;
    final pts = h.hazardPointsNear(me, radius);
    if (pts.isEmpty) return null;
    final bearings = pts.map((p) => Geo.bearing(me, p)).toList()..sort();
    var bestGap = 0.0, bestStart = 0.0;
    for (var i = 0; i < bearings.length; i++) {
      final a = bearings[i];
      final b = i == bearings.length - 1 ? bearings.first + 360 : bearings[i + 1];
      final gap = b - a;
      if (gap > bestGap) {
        bestGap = gap;
        bestStart = a;
      }
    }
    final center = (bestStart + bestGap / 2) % 360;
    final width = (bestGap - 20).clamp(0.0, 70.0);
    return SafeCone(center, width, pts.length);
  }
}

/// GPS helper around geolocator.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();
  LL? last;

  /// True once the OS granted location; the map's blue dot is only enabled then.
  bool granted = false;

  Future<bool> ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      return granted = perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<LL?> current() async {
    if (!await ensurePermission()) return last;
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      return last = LL(pos.latitude, pos.longitude);
    } catch (_) {
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) return last = LL(pos.latitude, pos.longitude);
      } catch (_) {}
      return last;
    }
  }

  Stream<LL> watch() => Geolocator.getPositionStream(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 8))
      .map((p) => last = LL(p.latitude, p.longitude));
}
