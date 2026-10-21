import 'dart:math' as math;

/// Lightweight lat/lon pair used across services (independent of the map plugin).
class LL {
  final double lat;
  final double lon;
  const LL(this.lat, this.lon);

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};
  factory LL.fromJson(Map<String, dynamic> j) =>
      LL((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble());

  @override
  String toString() => '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
}

class BBox {
  final double south, west, north, east;
  const BBox(this.south, this.west, this.north, this.east);

  factory BBox.around(LL c, double meters) {
    final dLat = meters / 111320.0;
    final dLon = meters / (111320.0 * math.cos(c.lat * math.pi / 180).abs().clamp(0.05, 1.0));
    return BBox(c.lat - dLat, c.lon - dLon, c.lat + dLat, c.lon + dLon);
  }

  LL get center => LL((south + north) / 2, (west + east) / 2);
  double get widthMeters => Geo.distance(LL(center.lat, west), LL(center.lat, east));

  bool contains(LL p) => p.lat >= south && p.lat <= north && p.lon >= west && p.lon <= east;
  bool containsBox(BBox o) =>
      o.south >= south && o.north <= north && o.west >= west && o.east <= east;

  BBox expand(double factor) {
    final h = (north - south) * (factor - 1) / 2;
    final w = (east - west) * (factor - 1) / 2;
    return BBox(south - h, west - w, north + h, east + w);
  }

  String get overpass =>
      '${south.toStringAsFixed(5)},${west.toStringAsFixed(5)},${north.toStringAsFixed(5)},${east.toStringAsFixed(5)}';
  String get esriEnvelope =>
      '${west.toStringAsFixed(5)},${south.toStringAsFixed(5)},${east.toStringAsFixed(5)},${north.toStringAsFixed(5)}';

  Map<String, dynamic> toJson() => {'s': south, 'w': west, 'n': north, 'e': east};
  factory BBox.fromJson(Map<String, dynamic> j) => BBox((j['s'] as num).toDouble(),
      (j['w'] as num).toDouble(), (j['n'] as num).toDouble(), (j['e'] as num).toDouble());
}

class Geo {
  static const double earthR = 6371008.8;
  static double _rad(double d) => d * math.pi / 180.0;
  static double _deg(double r) => r * 180.0 / math.pi;

  /// Great-circle distance in meters.
  static double distance(LL a, LL b) {
    final dLat = _rad(b.lat - a.lat);
    final dLon = _rad(b.lon - a.lon);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * earthR * math.asin(math.min(1.0, math.sqrt(h)));
  }

  /// Initial bearing from a to b, degrees 0..360 (0 = north).
  static double bearing(LL a, LL b) {
    final p1 = _rad(a.lat), p2 = _rad(b.lat), dl = _rad(b.lon - a.lon);
    final y = math.sin(dl) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
    return (_deg(math.atan2(y, x)) + 360) % 360;
  }

  /// Destination point given start, bearing (deg) and distance (m).
  static LL destination(LL a, double bearingDeg, double meters) {
    final d = meters / earthR;
    final b = _rad(bearingDeg);
    final p1 = _rad(a.lat), l1 = _rad(a.lon);
    final p2 = math.asin(math.sin(p1) * math.cos(d) + math.cos(p1) * math.sin(d) * math.cos(b));
    final l2 = l1 + math.atan2(math.sin(b) * math.sin(d) * math.cos(p1),
        math.cos(d) - math.sin(p1) * math.sin(p2));
    return LL(_deg(p2), (_deg(l2) + 540) % 360 - 180);
  }

  /// Distance from point p to segment ab in meters (local equirectangular projection).
  static double pointToSegment(LL p, LL a, LL b) {
    final k = math.cos(_rad(p.lat));
    final ax = (a.lon - p.lon) * k * 111320.0, ay = (a.lat - p.lat) * 110574.0;
    final bx = (b.lon - p.lon) * k * 111320.0, by = (b.lat - p.lat) * 110574.0;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    double t = len2 == 0 ? 0 : -(ax * dx + ay * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    return math.sqrt(cx * cx + cy * cy);
  }

  static double pointToLine(LL p, List<LL> line) {
    if (line.isEmpty) return double.infinity;
    if (line.length == 1) return distance(p, line.first);
    var best = double.infinity;
    for (var i = 0; i < line.length - 1; i++) {
      final d = pointToSegment(p, line[i], line[i + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  static double lineLength(List<LL> line) {
    var t = 0.0;
    for (var i = 0; i < line.length - 1; i++) {
      t += distance(line[i], line[i + 1]);
    }
    return t;
  }

  /// Ray-casting point-in-ring.
  static bool inRing(LL p, List<LL> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i].lon, yi = ring[i].lat, xj = ring[j].lon, yj = ring[j].lat;
      final intersect =
          ((yi > p.lat) != (yj > p.lat)) && (p.lon < (xj - xi) * (p.lat - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// GeoJSON geometry (Polygon / MultiPolygon) contains point.
  static bool geometryContains(Map<String, dynamic>? geom, LL p) {
    if (geom == null) return false;
    final type = geom['type'];
    final coords = geom['coordinates'];
    if (type == 'Polygon') return _polyContains(coords as List, p);
    if (type == 'MultiPolygon') {
      for (final poly in coords as List) {
        if (_polyContains(poly as List, p)) return true;
      }
    }
    return false;
  }

  static bool _polyContains(List rings, LL p) {
    if (rings.isEmpty) return false;
    if (!inRing(p, ringOf(rings.first as List))) return false;
    for (var i = 1; i < rings.length; i++) {
      if (inRing(p, ringOf(rings[i] as List))) return false; // hole
    }
    return true;
  }

  static List<LL> ringOf(List coords) => coords
      .map((c) => LL(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()))
      .toList();

  /// Approximate distance from p to a polygon's boundary (0 if inside).
  static double distanceToGeometry(Map<String, dynamic>? geom, LL p) {
    if (geom == null) return double.infinity;
    if (geometryContains(geom, p)) return 0;
    var best = double.infinity;
    void ringDist(List ring) {
      final d = pointToLine(p, ringOf(ring));
      if (d < best) best = d;
    }

    final type = geom['type'];
    final coords = geom['coordinates'];
    if (type == 'Polygon') {
      for (final r in coords as List) {
        ringDist(r as List);
      }
    } else if (type == 'MultiPolygon') {
      for (final poly in coords as List) {
        for (final r in poly as List) {
          ringDist(r as List);
        }
      }
    }
    return best;
  }

  static String compass(double bearing) {
    const dirs = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    return dirs[((bearing % 360) / 22.5).round() % 16];
  }

  /// Human friendly imperial distance.
  static String fmtDist(double meters) {
    if (meters.isInfinite || meters.isNaN) return '—';
    final yards = meters * 1.09361;
    if (yards < 1000) return '${yards.round()} yd';
    final miles = meters / 1609.344;
    return miles < 10 ? '${miles.toStringAsFixed(1)} mi' : '${miles.round()} mi';
  }

  static String fmtMiles(double meters) => '${(meters / 1609.344).toStringAsFixed(1)} mi';

  static String fmtDuration(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    if (h == 0) return '$m min';
    return '${h}h ${m}m';
  }

  /// Meters per screen pixel for MapLibre (512px tiles) at zoom z and latitude.
  static double metersPerPixel(double zoom, double lat) =>
      40075016.686 * math.cos(_rad(lat)) / (512 * math.pow(2, zoom));
}

/// NOAA sunrise/sunset (accurate to ~1 minute), returns local DateTime.
class Sun {
  static DateTime? _calc(DateTime date, LL p, bool rise) {
    const zenith = 90.833;
    final n = date.difference(DateTime(date.year, 1, 1)).inDays + 1;
    final lngHour = p.lon / 15.0;
    final t = n + ((rise ? 6 : 18) - lngHour) / 24.0;
    final m = (0.9856 * t) - 3.289;
    var l = m + (1.916 * math.sin(m * math.pi / 180)) + (0.020 * math.sin(2 * m * math.pi / 180)) + 282.634;
    l = (l + 360) % 360;
    var ra = math.atan(0.91764 * math.tan(l * math.pi / 180)) * 180 / math.pi;
    ra = (ra + 360) % 360;
    final lQuad = (l / 90).floor() * 90;
    final raQuad = (ra / 90).floor() * 90;
    ra = (ra + (lQuad - raQuad)) / 15.0;
    final sinDec = 0.39782 * math.sin(l * math.pi / 180);
    final cosDec = math.cos(math.asin(sinDec));
    final cosH = (math.cos(zenith * math.pi / 180) - (sinDec * math.sin(p.lat * math.pi / 180))) /
        (cosDec * math.cos(p.lat * math.pi / 180));
    if (cosH > 1 || cosH < -1) return null;
    var h = rise ? 360 - math.acos(cosH) * 180 / math.pi : math.acos(cosH) * 180 / math.pi;
    h = h / 15.0;
    final tt = h + ra - (0.06571 * t) - 6.622;
    var ut = (tt - lngHour) % 24;
    if (ut < 0) ut += 24;
    final base = DateTime.utc(date.year, date.month, date.day);
    var result = base.add(Duration(seconds: (ut * 3600).round()));
    // Ensure the result falls on the requested local day.
    final local = result.toLocal();
    if (local.day != date.day) {
      result = local.isAfter(DateTime(date.year, date.month, date.day, 23, 59))
          ? result.subtract(const Duration(days: 1))
          : result.add(const Duration(days: 1));
    }
    return result.toLocal();
  }

  static DateTime? sunrise(DateTime date, LL p) => _calc(date, p, true);
  static DateTime? sunset(DateTime date, LL p) => _calc(date, p, false);
}

String fmtTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String fmtDay(DateTime t) => '${_wd[t.weekday - 1]} ${_mo[t.month - 1]} ${t.day}';
String fmtWeekday(DateTime t) => _wd[t.weekday - 1];
