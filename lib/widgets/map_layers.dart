import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../services/clearance.dart';
import '../services/geo.dart';

/// Free, keyless vector basemap (OpenFreeMap, OSM data).
const basemapStyle = 'https://tiles.openfreemap.org/styles/dark';

enum MapMode { clear, land, trails }

const _empty = {'type': 'FeatureCollection', 'features': <dynamic>[]};

LatLng ll(LL p) => LatLng(p.lat, p.lon);
LL toLL(LatLng p) => LL(p.latitude, p.longitude);

/// Installs and updates all app overlays on a MapLibre controller.
class MapLayers {
  final MapLibreMapController c;
  bool ready = false;
  double _bakedLat = 0;
  MapLayers(this.c);

  static Future<Uint8List> _hatch(Color color) async {
    const s = 16.0;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..isAntiAlias = true;
    for (var x = -s; x <= s * 2; x += 8) {
      canvas.drawLine(Offset(x, s), Offset(x + s, 0), paint);
    }
    final img = await rec.endRecording().toImage(s.toInt(), s.toInt());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  /// Width (px) of a line representing a ±[meters] buffer, as a zoom expression.
  static List<dynamic> metersWidth(double meters, double lat) {
    double w(double z) => (2 * meters) / Geo.metersPerPixel(z, lat);
    return [
      'interpolate',
      ['exponential', 2],
      ['zoom'],
      8, w(8),
      20, w(20),
    ];
  }

  static List<dynamic> metersRadius(double meters, double lat) {
    double w(double z) => meters / Geo.metersPerPixel(z, lat);
    return [
      'interpolate',
      ['exponential', 2],
      ['zoom'],
      8, w(8),
      20, w(20),
    ];
  }

  Future<void> install({required double lat, bool withCone = false}) async {
    _bakedLat = lat;
    try {
      await c.addImage('hatch-red', await _hatch(const Color(0xCCE0605A)));
      await c.addImage('hatch-amber', await _hatch(const Color(0xAAE0A84F)));
    } catch (_) {}
    for (final s in ['land', 'closures', 'hazlines', 'hazpois', 'sel', 'pin', 'track', 'route', 'cone']) {
      await c.addGeoJsonSource(s, _empty);
    }
    // Land fills (Clear-to-shoot colours by status).
    await c.addFillLayer('land', 'land-clear',
        const FillLayerProperties(
          fillColor: [
            'match', ['get', 'status'],
            'allowed', '#8FC79A',
            'restricted', '#E0A84F',
            'check', '#E0A84F',
            '#E0605A'
          ],
          fillOpacity: [
            'match', ['get', 'status'],
            'allowed', 0.30,
            'restricted', 0.16,
            'check', 0.14,
            0.10
          ],
        ),
        enableInteraction: false);
    await c.addFillLayer('land', 'land-hatch', const FillLayerProperties(fillPattern: 'hatch-red', fillOpacity: 0.55),
        filter: ['in', ['get', 'status'], ['literal', ['prohibited', 'unknown']]], enableInteraction: false);
    await c.addFillLayer('land', 'land-hatch-r', const FillLayerProperties(fillPattern: 'hatch-amber', fillOpacity: 0.45),
        filter: ['in', ['get', 'status'], ['literal', ['restricted']]], enableInteraction: false);
    // Land mode: colour by manager.
    await c.addFillLayer('land', 'land-mgr',
        const FillLayerProperties(fillColor: ['get', 'color'], fillOpacity: 0.38, visibility: 'none'),
        enableInteraction: false);
    await c.addLineLayer('land', 'land-edge',
        const LineLayerProperties(
          lineColor: [
            'match', ['get', 'status'],
            'allowed', '#A9DDB2',
            'restricted', '#E0A84F',
            'check', '#E0A84F',
            '#E0605A'
          ],
          lineWidth: 1.2,
          lineOpacity: 0.65,
        ),
        enableInteraction: false);
    // Site closures.
    await c.addFillLayer('closures', 'closure-fill', const FillLayerProperties(fillPattern: 'hatch-red', fillOpacity: 0.7),
        enableInteraction: false);
    await c.addLineLayer('closures', 'closure-edge',
        const LineLayerProperties(lineColor: '#E0605A', lineWidth: 2.0, lineDasharray: [2, 1.5]),
        enableInteraction: false);
    // Buffers (muted rose) around every road/track/path, buildings and campsites.
    await c.addLineLayer('hazlines', 'buffer-lines',
        LineLayerProperties(
          lineColor: '#C98A8F',
          lineOpacity: 0.42,
          lineWidth: metersWidth(bufferMeters, lat),
          lineCap: 'round',
          lineJoin: 'round',
        ),
        minzoom: 11,
        enableInteraction: false);
    await c.addCircleLayer('hazpois', 'buffer-pois',
        CircleLayerProperties(
          circleColor: '#C98A8F',
          circleOpacity: 0.42,
          circleRadius: metersRadius(bufferMeters, lat),
        ),
        minzoom: 11,
        enableInteraction: false);
    // Roads (thin) and trails (dotted orange).
    await c.addLineLayer('hazlines', 'roads',
        const LineLayerProperties(lineColor: '#D9A1A6', lineWidth: 1.2, lineOpacity: 0.8),
        filter: ['==', ['get', 'trail'], 0], minzoom: 11, enableInteraction: false);
    await c.addLineLayer('hazlines', 'trails',
        const LineLayerProperties(
          lineColor: '#F0A05A',
          lineWidth: ['interpolate', ['linear'], ['zoom'], 11, 1.6, 16, 4.0],
          lineDasharray: [1.2, 1.0],
          lineCap: 'round',
        ),
        filter: ['==', ['get', 'trail'], 1], minzoom: 11, enableInteraction: false);
    await c.addLineLayer('sel', 'sel-glow',
        const LineLayerProperties(lineColor: '#F0A05A', lineWidth: 10, lineOpacity: 0.35, lineBlur: 4),
        enableInteraction: false);
    await c.addLineLayer('sel', 'sel-line',
        const LineLayerProperties(lineColor: '#FFD2A6', lineWidth: 3.5, lineCap: 'round', lineJoin: 'round'),
        enableInteraction: false);
    await c.addLineLayer('route', 'route-line',
        const LineLayerProperties(lineColor: '#F2F4F5', lineWidth: 2.5, lineDasharray: [2, 2], lineOpacity: 0.8),
        enableInteraction: false);
    await c.addLineLayer('track', 'track-line',
        const LineLayerProperties(lineColor: '#A33445', lineWidth: 4.5, lineCap: 'round', lineJoin: 'round'),
        enableInteraction: false);
    if (withCone) {
      await c.addFillLayer('cone', 'cone-fill', const FillLayerProperties(fillColor: '#8FC79A', fillOpacity: 0.32),
          enableInteraction: false);
      await c.addLineLayer('cone', 'cone-edge', const LineLayerProperties(lineColor: '#A9DDB2', lineWidth: 2),
          enableInteraction: false);
    }
    await c.addCircleLayer('pin', 'pin-glow',
        const CircleLayerProperties(circleColor: '#A33445', circleRadius: 16, circleOpacity: 0.35, circleBlur: 0.6),
        enableInteraction: false);
    await c.addCircleLayer('pin', 'pin-dot',
        const CircleLayerProperties(
            circleColor: '#A33445', circleRadius: 7.5, circleStrokeColor: '#FFFFFF', circleStrokeWidth: 2.5),
        enableInteraction: false);
    ready = true;
  }

  Future<void> setMode(MapMode m) async {
    if (!ready) return;
    final clear = m == MapMode.clear;
    final land = m == MapMode.land;
    await c.setLayerVisibility('land-clear', clear || m == MapMode.trails);
    await c.setLayerVisibility('land-hatch', clear);
    await c.setLayerVisibility('land-hatch-r', clear);
    await c.setLayerVisibility('land-mgr', land);
    await c.setLayerVisibility('land-edge', true);
    await c.setLayerVisibility('buffer-lines', clear);
    await c.setLayerVisibility('buffer-pois', clear);
    await c.setLayerVisibility('roads', !clear);
    await c.setLayerVisibility('trails', true);
    await c.setLayerVisibility('closure-fill', !land);
  }

  Future<void> maybeRebake(double lat) async {
    if (!ready || (lat - _bakedLat).abs() < 1.0) return;
    _bakedLat = lat;
    try {
      await c.setLayerProperties(
          'buffer-lines',
          LineLayerProperties(
            lineColor: '#C98A8F',
            lineOpacity: 0.42,
            lineWidth: metersWidth(bufferMeters, lat),
            lineCap: 'round',
            lineJoin: 'round',
          ));
      await c.setLayerProperties(
          'buffer-pois',
          CircleLayerProperties(
              circleColor: '#C98A8F', circleOpacity: 0.42, circleRadius: metersRadius(bufferMeters, lat)));
    } catch (_) {}
  }

  Future<void> setSource(String id, Map<String, dynamic> fc) async {
    if (!ready) return;
    try {
      await c.setGeoJsonSource(id, fc);
    } catch (_) {}
  }

  Future<void> setPin(LL? p) => setSource('pin', p == null ? _empty : point(p));

  Future<void> setLine(String id, List<LL> line) => setSource(id, lineFc(line));

  static Map<String, dynamic> point(LL p) => {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': <String, dynamic>{},
            'geometry': {'type': 'Point', 'coordinates': [p.lon, p.lat]}
          }
        ]
      };

  static Map<String, dynamic> lineFc(List<LL> line) => line.length < 2
      ? _empty
      : {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'properties': <String, dynamic>{},
              'geometry': {
                'type': 'LineString',
                'coordinates': [for (final p in line) [p.lon, p.lat]]
              }
            }
          ]
        };

  static Map<String, dynamic> coneFc(LL me, double center, double width, double range) {
    final pts = <List<double>>[[me.lon, me.lat]];
    final steps = math.max(4, (width / 5).round());
    for (var i = 0; i <= steps; i++) {
      final b = center - width / 2 + width * i / steps;
      final p = Geo.destination(me, b, range);
      pts.add([p.lon, p.lat]);
    }
    pts.add([me.lon, me.lat]);
    return {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': <String, dynamic>{},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [pts]
          }
        }
      ]
    };
  }
}

Future<BBox?> visibleBox(MapLibreMapController c) async {
  try {
    final b = await c.getVisibleRegion();
    return BBox(b.southwest.latitude, b.southwest.longitude, b.northeast.latitude, b.northeast.longitude);
  } catch (_) {
    return null;
  }
}
