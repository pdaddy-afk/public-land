import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../services/clearance.dart';
import '../services/geo.dart';
import '../services/land_service.dart';
import '../services/osm_service.dart';
import '../services/store.dart';
import '../widgets/glass.dart';
import '../widgets/map_layers.dart';
import 'search_sheet.dart';
import 'spot_sheet.dart';
import 'trail_sheet.dart';

class MapScreen extends StatefulWidget {
  final LL center;
  final double zoom;
  final MapMode mode;
  final LL? pin;
  final String? pinName;
  const MapScreen({super.key, required this.center, this.zoom = 13, this.mode = MapMode.clear, this.pin, this.pinName});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapLibreMapController? _c;
  MapLayers? _layers;
  late MapMode _mode = widget.mode;
  Timer? _debounce;
  bool _loadingLand = false, _loadingOsm = false;
  String? _banner;
  Clearance? _status;
  bool _statusIsGps = false;
  LL? _me;
  StreamSubscription<LL>? _gps;
  double _zoom = 13;
  List<Trail> _trails = [];
  int _reqSeq = 0;

  @override
  void initState() {
    super.initState();
    _zoom = widget.zoom;
    _startGps();
  }

  Future<void> _startGps() async {
    final me = await LocationService.instance.current();
    if (!mounted) return;
    setState(() => _me = me);
    if (await LocationService.instance.ensurePermission()) {
      _gps = LocationService.instance.watch().listen((p) {
        _me = p;
        _refreshStatus();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _gps?.cancel();
    super.dispose();
  }

  Future<void> _onStyle() async {
    final c = _c;
    if (c == null) return;
    final layers = MapLayers(c);
    await layers.install(lat: widget.center.lat);
    _layers = layers;
    await LandService.instance.ensureLoaded();
    await layers.setSource('closures', LandService.instance.activeClosureGeojson());
    await layers.setMode(_mode);
    if (widget.pin != null) await layers.setPin(widget.pin);
    // Offline: preload cached data for this area if any.
    _loadCachedArea();
    _scheduleLoad(immediate: true);
  }

  void _loadCachedArea() {
    final s = Store.instance;
    for (final key in s.offlineAreas) {
      final land = s.getCache('land:$key');
      final osm = s.getCache('osm:$key');
      if (land == null || osm == null) continue;
      try {
        final h = Hazards.fromCache(osm);
        if (!h.box.contains(widget.center)) continue;
        LandService.instance.importCache(land).then((_) => _pushData());
        OsmService.instance.last = h;
        _pushData();
        break;
      } catch (_) {}
    }
  }

  void _scheduleLoad({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: immediate ? 50 : 700), _load);
  }

  Future<void> _load() async {
    final c = _c;
    if (c == null || _layers == null) return;
    final seq = ++_reqSeq;
    final box = await visibleBox(c);
    final zoom = c.cameraPosition?.zoom ?? _zoom;
    _zoom = zoom;
    if (box == null) return;
    await _layers!.maybeRebake(box.center.lat);
    if (zoom < 8.5) {
      setState(() => _banner = 'Zoom in to see public land and shooting status');
      return;
    }
    setState(() {
      _banner = null;
      _loadingLand = true;
    });
    try {
      await LandService.instance.fetch(box.expand(1.4), zoom);
      if (seq != _reqSeq) return;
      await _pushLand();
    } catch (e) {
      if (mounted) setState(() => _banner = 'Land data unavailable right now (PAD-US). Showing what is cached.');
    } finally {
      if (mounted) setState(() => _loadingLand = false);
    }
    if (zoom >= 12.2 && box.widthMeters < 16000) {
      setState(() => _loadingOsm = true);
      try {
        await OsmService.instance.fetch(box.expand(1.3));
        if (seq != _reqSeq) return;
        await _pushOsm();
      } catch (e) {
        if (mounted) setState(() => _banner = 'Roads and trails are busy (OpenStreetMap Overpass). Try again in a moment.');
      } finally {
        if (mounted) setState(() => _loadingOsm = false);
      }
    } else if (zoom < 12.2) {
      if (mounted && _mode != MapMode.land) {
        setState(() => _banner = 'Zoom in closer to see trails and 150-yard buffers');
      }
    }
    _refreshStatus();
  }

  Future<void> _pushData() async {
    await _pushLand();
    await _pushOsm();
    _refreshStatus();
  }

  Future<void> _pushLand() async {
    await _layers?.setSource('land', LandService.instance.parcelsGeojson(LandService.instance.lastParcels));
  }

  Future<void> _pushOsm() async {
    final h = OsmService.instance.last;
    if (h == null) return;
    await _layers?.setSource('hazlines', h.linesGeojson());
    await _layers?.setSource('hazpois', h.poisGeojson());
    _trails = OsmService.instance.trails(h);
  }

  Future<void> _refreshStatus() async {
    final c = _c;
    if (c == null) return;
    LL target;
    var gps = false;
    final box = OsmService.instance.last?.box ?? LandService.instance.lastBox;
    if (_me != null && box != null && box.contains(_me!)) {
      target = _me!;
      gps = true;
    } else {
      final cam = c.cameraPosition;
      if (cam == null) return;
      target = toLL(cam.target);
    }
    final st = ClearanceService.evaluateLocal(target, OsmService.instance.last);
    if (mounted) {
      setState(() {
        _status = st;
        _statusIsGps = gps;
      });
    }
  }

  Future<void> _setMode(MapMode m) async {
    setState(() => _mode = m);
    await _layers?.setMode(m);
    _refreshStatus();
  }

  void _onTap(LL p) async {
    if (_mode == MapMode.trails || _mode == MapMode.clear) {
      final t = _nearestTrail(p);
      if (t != null && _mode == MapMode.trails) {
        await _layers?.setLine('sel', t.line);
        if (!mounted) return;
        await showGlassSheet(context, (_) => TrailSheet(trail: t));
        await _layers?.setLine('sel', const []);
        return;
      }
    }
    await _layers?.setPin(p);
    if (!mounted) return;
    await showGlassSheet(context, (_) => SpotSheet(point: p));
    await _layers?.setPin(widget.pin);
  }

  Trail? _nearestTrail(LL p) {
    if (_trails.isEmpty) return null;
    final tol = Geo.metersPerPixel(_zoom, p.lat) * 28;
    Trail? best;
    var bd = tol;
    for (final t in _trails) {
      final d = Geo.pointToLine(p, t.line);
      if (d < bd) {
        bd = d;
        best = t;
      }
    }
    return best;
  }

  Future<void> _locate() async {
    final me = await LocationService.instance.current();
    if (me == null) {
      if (mounted) toast(context, 'Location is off or not allowed. Turn it on to see your status.');
      return;
    }
    _me = me;
    await _c?.animateCamera(CameraUpdate.newLatLngZoom(ll(me), 14.5));
  }

  Future<void> _search() async {
    final place = await showGlassSheet<SearchPick>(context, (_) => SearchSheet(bias: _me ?? widget.center));
    if (place == null) return;
    await _c?.animateCamera(CameraUpdate.newLatLngZoom(ll(place.p), 13.5));
    await _layers?.setPin(place.p);
  }

  Future<void> _offline() async {
    final c = _c;
    if (c == null) return;
    if (kIsWeb) {
      toast(context, 'Offline maps need the Android app. The web app caches only what you have viewed.');
      return;
    }
    final box = await visibleBox(c);
    if (box == null) return;
    if (!mounted) return;
    await showGlassSheet(context, (_) => OfflineSheet(box: box, zoom: _zoom));
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        Positioned.fill(
          child: MapLibreMap(
            styleString: basemapStyle,
            initialCameraPosition: CameraPosition(target: ll(widget.center), zoom: widget.zoom),
            onMapCreated: (c) => _c = c,
            onStyleLoadedCallback: _onStyle,
            trackCameraPosition: true,
            myLocationEnabled: true,
            myLocationTrackingMode: MyLocationTrackingMode.none,
            compassEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomLeft,
            onCameraIdle: () => _scheduleLoad(),
            onMapClick: (pt, latLng) => _onTap(toLL(latLng)),
          ),
        ),
        // Top controls
        Positioned(
          top: pad.top + 10,
          left: 14,
          right: 14,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              _roundIcon(Icons.arrow_back_rounded, () => Navigator.maybePop(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Glass(
                  radius: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  onTap: _search,
                  child: const Row(children: [
                    Icon(Icons.search_rounded, color: C.text2),
                    SizedBox(width: 10),
                    Expanded(child: Text('Search spots or places', style: TextStyle(fontSize: 17, color: C.text2))),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: PillSegments(
                  labels: const ['Clear to Shoot', 'Land', 'Trails'],
                  index: _mode.index,
                  activeColor: _mode == MapMode.clear ? C.sageDeep : C.burgundy,
                  onChanged: (i) => _setMode(MapMode.values[i]),
                ),
              ),
            ]),
            if (_banner != null) ...[
              const SizedBox(height: 8),
              Glass(
                radius: 18,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(_banner!, style: const TextStyle(fontSize: 15, color: C.text2)),
              ),
            ],
          ]),
        ),
        // Right tool column
        Positioned(
          right: 14,
          top: pad.top + 150,
          child: Glass(
            radius: 26,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(children: [
              _tool(Icons.my_location_rounded, 'Locate', _locate),
              _tool(Icons.download_for_offline_outlined, 'Offline', _offline),
              _tool(Icons.layers_outlined, 'Legend', () => showGlassSheet(context, (_) => const LegendSheet())),
              if (_loadingLand || _loadingOsm)
                const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: C.sage))),
            ]),
          ),
        ),
        // Bottom status card
        Positioned(
          left: 14,
          right: 14,
          bottom: pad.bottom + 14,
          child: _statusCard(),
        ),
      ]),
    );
  }

  Widget _statusCard() {
    final s = _status;
    if (s == null) {
      return const Glass(
        child: Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.sage)),
          SizedBox(width: 12),
          Text('Checking land status…', style: TextStyle(fontSize: 18)),
        ]),
      );
    }
    final color = s.clear ? C.sage : (s.land.status == ShootStatus.allowed ? C.rose : C.status(s.land.status));
    return Glass(
      onTap: () => showGlassSheet(context, (_) => SpotSheet(point: s.p)),
      child: Row(children: [
        StatusDot(color, size: 14),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(_statusIsGps ? s.headline : (s.clear ? 'Map center is clear' : 'Map center: not clear'),
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(
              s.clear
                  ? '${s.subline} · ${Geo.fmtDist(s.roadM)} from road'
                  : (s.reasons.isEmpty ? s.subline : s.reasons.first),
              style: const TextStyle(fontSize: 16, color: C.text2),
            ),
            if (s.land.checkLocalOrders && s.land.parcel != null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Check local orders', style: TextStyle(fontSize: 15, color: C.amber, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: C.text2),
      ]),
    );
  }

  Widget _roundIcon(IconData i, VoidCallback onTap) => Glass(
        radius: 26,
        padding: const EdgeInsets.all(13),
        onTap: onTap,
        child: Icon(i, color: C.text),
      );

  Widget _tool(IconData i, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: IconButton(onPressed: onTap, icon: Icon(i, color: C.text, size: 26), padding: const EdgeInsets.all(12)),
      );
}

class LegendSheet extends StatelessWidget {
  const LegendSheet({super.key});
  @override
  Widget build(BuildContext context) {
    Widget row(Color c, String t, String d) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 26,
                height: 18,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(5))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                Text(d, style: const TextStyle(fontSize: 15, color: C.text2)),
              ]),
            ),
          ]),
        );
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Map legend', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        row(C.sage, 'Shootable public land', 'BLM or Forest land with no known closure'),
        row(C.rose, '150-yard buffer', 'Around roads, tracks, trails, buildings and campsites (36 CFR 261.10)'),
        row(C.amber, 'Restricted / check rules', 'Closure order, seasonal fire order, or rules vary'),
        row(C.red, 'No shooting', 'Parks, refuges, military, tribal, local or private land (hatched)'),
        row(C.trail, 'Trails', 'OpenStreetMap paths and tracks'),
        const SizedBox(height: 10),
        const Text('Land mode colours',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        row(const Color(0xFFE3C26A), 'BLM', 'Bureau of Land Management'),
        row(const Color(0xFF6FAE6F), 'USFS', 'National Forest'),
        row(const Color(0xFF6E9BD1), 'State', 'State parks, wildlife areas, trust land'),
        row(const Color(0xFF9C7BC4), 'NPS', 'National Park Service'),
        row(const Color(0xFF5FB3B3), 'FWS', 'Fish & Wildlife refuges'),
        row(const Color(0xFFB06A6A), 'DOD', 'Military'),
        const SizedBox(height: 10),
        const Text(
          'Status is a guide, not legal advice. Always obey posted signs, fire restrictions and local orders.',
          style: TextStyle(fontSize: 15, color: C.text3),
        ),
      ]),
    );
  }
}

/// Download the current view for offline use (Android only).
class OfflineSheet extends StatefulWidget {
  final BBox box;
  final double zoom;
  const OfflineSheet({super.key, required this.box, required this.zoom});
  @override
  State<OfflineSheet> createState() => _OfflineSheetState();
}

class _OfflineSheetState extends State<OfflineSheet> {
  double? _progress;
  String _msg = '';
  bool _done = false;

  Future<void> _go() async {
    setState(() {
      _progress = 0;
      _msg = 'Saving land and trail data…';
    });
    final key = widget.box.overpass;
    final store = Store.instance;
    try {
      await LandService.instance.fetch(widget.box, widget.zoom.clamp(11, 14));
      await store.putCache('land:$key', LandService.instance.exportCache());
      final h = await OsmService.instance.fetch(widget.box);
      await store.putCache('osm:$key', h.toCache());
      final areas = store.offlineAreas.where((a) => a != key).toList()..insert(0, key);
      await store.setOfflineAreas(areas.take(5).toList());
    } catch (e) {
      setState(() => _msg = 'Could not save land/trail data: $e');
    }
    setState(() => _msg = 'Downloading map tiles…');
    try {
      await downloadOfflineRegion(
        OfflineRegionDefinition(
          bounds: LatLngBounds(
              southwest: LatLng(widget.box.south, widget.box.west), northeast: LatLng(widget.box.north, widget.box.east)),
          mapStyleUrl: basemapStyle,
          minZoom: (widget.zoom - 3).clamp(6, 14).toDouble(),
          maxZoom: (widget.zoom + 2).clamp(10, 15).toDouble(),
        ),
        metadata: {'name': 'Area ${DateTime.now().toIso8601String().substring(0, 10)}'},
        onEvent: (e) {
          if (!mounted) return;
          if (e is InProgress) {
            setState(() => _progress = e.progress / 100.0);
          } else if (e is Success) {
            setState(() {
              _progress = 1;
              _done = true;
              _msg = 'Saved. This area works without signal.';
            });
          } else if (e is Error) {
            setState(() => _msg = 'Tile download failed: ${e.cause.message}');
          }
        },
      );
    } catch (e) {
      setState(() => _msg = 'Tile download failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Save this area offline', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(
        'Saves the basemap tiles for the area on screen (zoom ${(widget.zoom - 3).clamp(6, 14).round()}–${(widget.zoom + 2).clamp(10, 15).round()}), '
        'plus land status, roads, trails and buffers. About ${(widget.box.widthMeters / 1609).toStringAsFixed(1)} mi wide.',
        style: const TextStyle(fontSize: 16, color: C.text2),
      ),
      const SizedBox(height: 8),
      const Text('Weather and drive times still need a connection.', style: TextStyle(fontSize: 15, color: C.text3)),
      const SizedBox(height: 16),
      if (_progress != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: _progress, minHeight: 10, color: C.sage, backgroundColor: Colors.white12),
        ),
        const SizedBox(height: 10),
        Text(_msg, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
      ],
      SizedBox(
        width: double.infinity,
        child: _done
            ? GlassButton('Done', onPressed: () => Navigator.pop(context))
            : PrimaryButton('Download', icon: Icons.download_rounded, busy: _progress != null && !_done, onPressed: _go),
      ),
    ]);
  }
}
