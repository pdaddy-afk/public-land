import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../services/clearance.dart';
import '../services/geo.dart';
import '../services/handoff.dart';
import '../services/models.dart';
import '../services/store.dart';
import '../widgets/glass.dart';
import '../widgets/map_layers.dart';
import 'onsite_screen.dart';

/// In-app follow-me map with a recorded GPS track toward the pin.
class NavigateScreen extends StatefulWidget {
  final LL dest;
  final String destName;
  final Trip? resume;
  const NavigateScreen({super.key, required this.dest, required this.destName, this.resume});
  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen> {
  MapLibreMapController? _c;
  MapLayers? _layers;
  StreamSubscription<LL>? _sub;
  late Trip _trip;
  LL? _me;
  bool _follow = true;
  DateTime _lastSave = DateTime.now();

  @override
  void initState() {
    super.initState();
    _trip = widget.resume ??
        Trip(id: newId(), title: widget.destName, dest: widget.dest, start: DateTime.now());
    _start();
  }

  Future<void> _start() async {
    if (!await LocationService.instance.ensurePermission()) {
      if (mounted) toast(context, 'Allow location to follow your track.');
      return;
    }
    await Store.instance.upsertTrip(_trip);
    _sub = LocationService.instance.watch().listen(_onPos);
    final me = await LocationService.instance.current();
    if (me != null) _onPos(me);
  }

  void _onPos(LL p) {
    _me = p;
    if (_trip.track.isEmpty || Geo.distance(_trip.track.last, p) > 6) _trip.track.add(p);
    _layers?.setLine('track', _trip.track);
    _layers?.setLine('route', [p, widget.dest]);
    if (_follow) _c?.animateCamera(CameraUpdate.newLatLng(ll(p)));
    if (DateTime.now().difference(_lastSave).inSeconds > 20) {
      _lastSave = DateTime.now();
      Store.instance.upsertTrip(_trip);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    Store.instance.upsertTrip(_trip);
    super.dispose();
  }

  Future<void> _onStyle() async {
    final c = _c;
    if (c == null) return;
    final l = MapLayers(c);
    await l.install(lat: widget.dest.lat);
    _layers = l;
    await l.setMode(MapMode.trails);
    await l.setPin(widget.dest);
    await l.setLine('track', _trip.track);
    if (_me != null) await l.setLine('route', [_me!, widget.dest]);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final me = _me;
    final remain = me == null ? null : Geo.distance(me, widget.dest);
    final brg = me == null ? null : Geo.bearing(me, widget.dest);
    final arrived = remain != null && remain < 150;
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: MapLibreMap(
            styleString: basemapStyle,
            initialCameraPosition: CameraPosition(target: ll(widget.dest), zoom: 14),
            onMapCreated: (c) => _c = c,
            onStyleLoadedCallback: _onStyle,
            myLocationEnabled: true,
            myLocationTrackingMode: MyLocationTrackingMode.none,
            onCameraTrackingDismissed: () => setState(() => _follow = false),
            compassEnabled: true,
          ),
        ),
        Positioned(
          top: pad.top + 10,
          left: 14,
          right: 14,
          child: Glass(
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, size: 26)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.destName,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                  Text(
                    remain == null
                        ? 'Waiting for GPS…'
                        : '${Geo.fmtDist(remain)} · head ${Geo.compass(brg!)} (${brg.round()}°) straight-line',
                    style: const TextStyle(fontSize: 16, color: C.text2),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        Positioned(
          right: 14,
          top: pad.top + 100,
          child: Glass(
            radius: 26,
            padding: const EdgeInsets.all(4),
            child: IconButton(
              onPressed: () {
                setState(() => _follow = true);
                if (_me != null) _c?.animateCamera(CameraUpdate.newLatLngZoom(ll(_me!), 15));
              },
              icon: Icon(Icons.navigation_rounded, color: _follow ? C.burgundyHi : C.text, size: 26),
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: pad.bottom + 14,
          child: Glass(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _stat('Tracked', Geo.fmtMiles(_trip.distanceM)),
                _stat('Time', Geo.fmtDuration(_trip.duration)),
              ]),
              const SizedBox(height: 12),
              if (arrived)
                PrimaryButton("I'm here: on-site view", icon: Icons.my_location_rounded, onPressed: _onsite)
              else
                Row(children: [
                  Expanded(child: GlassButton('Google Maps', icon: Icons.map_outlined, onPressed: () => Handoff.googleMaps(widget.dest))),
                  const SizedBox(width: 10),
                  Expanded(child: GlassButton('On-site', icon: Icons.explore_outlined, onPressed: _onsite)),
                ]),
              const SizedBox(height: 8),
              const Text('Keep the screen on while tracking. Background tracking is not supported in v1.',
                  style: TextStyle(fontSize: 13, color: C.text3)),
            ]),
          ),
        ),
      ]),
    );
  }

  void _onsite() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OnsiteScreen(trip: _trip)));
  }

  Widget _stat(String k, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 15, color: C.text3)),
          Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ]),
      );
}
