import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../services/clearance.dart';
import '../services/geo.dart';
import '../services/land_service.dart';
import '../services/models.dart';
import '../services/osm_service.dart';
import '../services/store.dart';
import '../services/weather_service.dart';
import '../widgets/glass.dart';
import '../widgets/map_layers.dart';
import 'pack_screen.dart';
import 'wrapup_screen.dart';

/// On-site: your position, safe-direction cone, nearest trail/road, sunset.
class OnsiteScreen extends StatefulWidget {
  final Trip trip;
  const OnsiteScreen({super.key, required this.trip});
  @override
  State<OnsiteScreen> createState() => _OnsiteScreenState();
}

class _OnsiteScreenState extends State<OnsiteScreen> {
  MapLibreMapController? _c;
  MapLayers? _layers;
  StreamSubscription<LL>? _sub;
  LL? _me;
  Clearance? _clr;
  SafeCone? _cone;
  WeatherSnapshot? _wx;
  bool _loading = true;
  LL? _lastEval;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final me = await LocationService.instance.current() ?? widget.trip.dest;
    _me = me;
    _evaluate(me);
    WeatherService.instance.get(me).then((w) {
      if (mounted) setState(() => _wx = w);
    }).catchError((_) {});
    if (await LocationService.instance.ensurePermission()) {
      _sub = LocationService.instance.watch().listen((p) {
        _me = p;
        if (widget.trip.track.isEmpty || Geo.distance(widget.trip.track.last, p) > 6) widget.trip.track.add(p);
        if (_lastEval == null || Geo.distance(_lastEval!, p) > 25) _evaluate(p);
      });
    }
  }

  Future<void> _evaluate(LL p) async {
    _lastEval = p;
    setState(() => _loading = true);
    try {
      await LandService.instance.fetch(BBox.around(p, 2500), 14);
    } catch (_) {}
    Hazards? h;
    try {
      h = await OsmService.instance.fetch(BBox.around(p, 1500));
    } catch (_) {
      h = OsmService.instance.last;
    }
    final clr = ClearanceService.evaluateLocal(p, h);
    final cone = SafeCone.compute(p, h);
    if (!mounted) return;
    setState(() {
      _clr = clr;
      _cone = cone;
      _loading = false;
    });
    final l = _layers;
    if (l != null) {
      await l.setSource('land', LandService.instance.parcelsGeojson(LandService.instance.lastParcels));
      if (h != null) {
        await l.setSource('hazlines', h.linesGeojson());
        await l.setSource('hazpois', h.poisGeojson());
      }
      await l.setSource(
          'cone',
          cone == null
              ? MapLayers.coneFc(p, 0, 0, 1)
              : MapLayers.coneFc(p, cone.centerDeg, math.max(cone.widthDeg, 8), 400));
      _c?.animateCamera(CameraUpdate.newLatLngZoom(ll(p), 15.2));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    Store.instance.upsertTrip(widget.trip);
    super.dispose();
  }

  Future<void> _onStyle() async {
    final c = _c;
    if (c == null) return;
    final l = MapLayers(c);
    await l.install(lat: widget.trip.dest.lat, withCone: true);
    _layers = l;
    await l.setMode(MapMode.clear);
    await l.setPin(widget.trip.dest);
    await l.setSource('closures', LandService.instance.activeClosureGeojson());
    if (_me != null) _evaluate(_me!);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final me = _me ?? widget.trip.dest;
    final sunset = Sun.sunset(DateTime.now(), me);
    final clr = _clr;
    final cone = _cone;
    final red = _wx?.redFlag ?? false;
    final clear = (clr?.clear ?? false) && !red;
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: MapLibreMap(
            styleString: basemapStyle,
            initialCameraPosition: CameraPosition(target: ll(me), zoom: 15),
            onMapCreated: (c) => _c = c,
            onStyleLoadedCallback: _onStyle,
            myLocationEnabled: true,
            myLocationTrackingMode: MyLocationTrackingMode.none,
          ),
        ),
        Positioned(
          top: pad.top + 10,
          left: 14,
          right: 14,
          child: Glass(
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, size: 26)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    StatusDot(clear ? C.sage : (clr == null ? C.text3 : C.rose), size: 13),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        clr == null ? 'Checking…' : (clear ? "You're clear to shoot" : 'Not clear to shoot'),
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: clear ? C.sage : C.rose),
                      ),
                    ),
                  ]),
                  if (clr != null)
                    Text(
                      red ? 'Red Flag / fire weather alert: no shooting' : (clear ? clr.subline : (clr.reasons.isEmpty ? '' : clr.reasons.first)),
                      style: const TextStyle(fontSize: 15, color: C.text2),
                    ),
                ]),
              ),
              if (_loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.sage)),
            ]),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: pad.bottom + 14,
          child: Glass(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                SizedBox(width: 92, height: 92, child: CustomPaint(painter: ConePainter(cone))),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Safe direction', style: TextStyle(fontSize: 15, color: C.text3)),
                    Text(
                      cone == null
                          ? (clr?.hazardsLoaded == true ? 'No mapped hazards within ½ mi' : 'Loading…')
                          : '${Geo.compass(cone.centerDeg)} · ${cone.centerDeg.round()}° ±${(cone.widthDeg / 2).round()}°',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    const Text('Away from mapped roads, trails and buildings. Confirm a safe backstop.',
                        style: TextStyle(fontSize: 14, color: C.text2)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _stat('Trail', clr == null ? '…' : Geo.fmtDist(clr.trailM)),
                _stat('Road', clr == null ? '…' : Geo.fmtDist(clr.roadM)),
                _stat('Sunset', sunset == null ? '—' : fmtTime(sunset)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: GlassButton('Pack list', icon: Icons.checklist_rounded, onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PackScreen(listId: 'trip:${widget.trip.id}', activity: widget.trip.activity, at: me)));
                  }),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton('Wrap up', icon: Icons.flag_rounded, onPressed: () {
                    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => WrapupScreen(trip: widget.trip)));
                  }),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _stat(String k, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 15, color: C.text3)),
          Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Compass rose with the safe sector highlighted (north up).
class ConePainter extends CustomPainter {
  final SafeCone? cone;
  ConePainter(this.cone);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = Colors.white.withValues(alpha: 0.06));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white24
          ..strokeWidth = 1.5);
    final k = cone;
    if (k != null) {
      final start = (k.centerDeg - math.max(k.widthDeg, 8) / 2 - 90) * math.pi / 180;
      final sweep = math.max(k.widthDeg, 8) * math.pi / 180;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, true,
          Paint()..color = C.sage.withValues(alpha: 0.55));
    }
    final tp = TextPainter(
        text: const TextSpan(text: 'N', style: TextStyle(color: C.text, fontSize: 13, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - r + 2));
    canvas.drawCircle(c, 4, Paint()..color = C.burgundyHi);
  }

  @override
  bool shouldRepaint(covariant ConePainter old) => old.cone != cone;
}
