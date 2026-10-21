import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../backend/backend_service.dart';
import '../services/clearance.dart';
import '../services/geo.dart';
import '../services/handoff.dart';
import '../services/land_service.dart';
import '../services/places_service.dart';
import '../services/store.dart';
import '../services/weather_service.dart';
import '../widgets/glass.dart';
import '../widgets/map_layers.dart';
import 'map_screen.dart';
import 'navigate_screen.dart';
import 'outing_screens.dart';
import 'search_sheet.dart';
import 'spot_sheet.dart';
import 'wrapup_screen.dart';

/// Neutral default when location is off (a public city center, not anyone's home).
const defaultCenter = LL(32.7157, -117.1611);

class HomeTabs extends StatefulWidget {
  const HomeTabs({super.key});
  @override
  State<HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<HomeTabs> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [const ExploreTab(), const TripsTab(), const SavedTab(), const ProfileTab()];
    return Scaffold(
      extendBody: true,
      body: AmbientBackground(child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Glass(
          radius: 30,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            _tabItem(0, Icons.explore_rounded, 'Explore'),
            _tabItem(1, Icons.backpack_outlined, 'Trips'),
            _tabItem(2, Icons.bookmark_rounded, 'Saved'),
            _tabItem(3, Icons.person_rounded, 'Profile'),
          ]),
        ),
      ),
    );
  }

  Widget _tabItem(int i, IconData icon, String label) {
    final on = _tab == i;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => setState(() => _tab = i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: on
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: C.burgundy.withValues(alpha: 0.35),
                  boxShadow: [BoxShadow(color: C.burgundy.withValues(alpha: 0.45), blurRadius: 14)],
                )
              : null,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: on ? Colors.white : C.text2, size: 26),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 14, color: on ? Colors.white : C.text2, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

// ───────────────────────────── Explore ─────────────────────────────

class ExploreTab extends StatefulWidget {
  const ExploreTab({super.key});
  @override
  State<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  LL? _me;
  String? _place;
  WeatherSnapshot? _wx;
  List<NearbyUnit>? _near;
  String? _nearErr;
  bool _usingDefault = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = await LocationService.instance.current();
    final c = me ?? defaultCenter;
    if (!mounted) return;
    setState(() {
      _me = c;
      _usingDefault = me == null;
    });
    PlacesService.reverse(c).then((p) {
      if (mounted) setState(() => _place = p);
    });
    WeatherService.instance.get(c).then((w) {
      if (mounted) setState(() => _wx = w);
    }).catchError((_) {});
    try {
      final n = await LandService.instance.nearby(c);
      if (mounted) setState(() => _near = n);
    } catch (e) {
      if (mounted) setState(() => _nearErr = 'Public land data is unavailable right now.');
    }
  }

  void _openMap({LL? at, MapMode mode = MapMode.clear, double zoom = 13, LL? pin}) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MapScreen(center: at ?? _me ?? defaultCenter, mode: mode, zoom: zoom, pin: pin)));
  }

  Future<void> _search() async {
    final pick = await showGlassSheet<SearchPick>(context, (_) => SearchSheet(bias: _me));
    if (pick == null) return;
    _openMap(at: pick.p, zoom: 13.5, pin: pick.p);
  }

  @override
  Widget build(BuildContext context) {
    final name = Store.instance.userName;
    final now = _wx?.now;
    final line = [
      _place ?? (_usingDefault ? 'Location off' : 'Locating…'),
      if (now != null) '${now.tempF}° ${now.short.toLowerCase()}',
    ].join(' · ');
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 30, 20, 120), children: [
          Text(name.isEmpty ? 'Hey there' : 'Hey $name', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(line, style: const TextStyle(fontSize: 20, color: C.text2)),
          if (_wx?.redFlag == true)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Glass(
                tint: C.red,
                opacity: 0.14,
                child: Row(children: [
                  const Icon(Icons.local_fire_department_rounded, color: C.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        '${_wx!.alerts.firstWhere((a) => a.isFire).event}: target shooting is suspended on BLM land in CA during Red Flag Warnings.',
                        style: const TextStyle(fontSize: 16)),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 20),
          Glass(
            radius: 30,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            onTap: _search,
            child: const Row(children: [
              Icon(Icons.search_rounded, color: C.text2, size: 26),
              SizedBox(width: 12),
              Text('Where to?', style: TextStyle(fontSize: 21, color: C.text2)),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _modeCard('Clear to Shoot', Icons.gps_fixed_rounded, C.sage, () => _openMap())),
            const SizedBox(width: 10),
            Expanded(child: _modeCard('Land', Icons.layers_rounded, const Color(0xFFE3C26A), () => _openMap(mode: MapMode.land, zoom: 10))),
            const SizedBox(width: 10),
            Expanded(child: _modeCard('Trails', Icons.hiking_rounded, C.trail, () => _openMap(mode: MapMode.trails))),
          ]),
          const SectionTitle('Near you'),
          if (_near == null && _nearErr == null)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: C.sage))),
          if (_nearErr != null) Text(_nearErr!, style: const TextStyle(color: C.amber, fontSize: 16)),
          if (_near != null && _near!.isEmpty)
            const Text('No BLM, Forest or state land within about 40 miles.', style: TextStyle(fontSize: 17, color: C.text2)),
          for (final n in _near ?? <NearbyUnit>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Glass(
                onTap: () => _openMap(at: n.nearest, zoom: 12.5, pin: n.nearest),
                child: Row(children: [
                  StatusDot(C.status(n.status)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.unit, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      Text(
                        '${n.distanceM == 0 ? "You're on it" : Geo.fmtDist(n.distanceM)} · ${managerInfo(n.manager).code} · ${n.status.label}'
                        '${n.checkLocal ? ' · check local orders' : ''}',
                        style: const TextStyle(fontSize: 16, color: C.text2),
                      ),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: C.text2),
                ]),
              ),
            ),
          if (Store.instance.spots.isNotEmpty) ...[
            const SectionTitle('Your spots'),
            for (final s in Store.instance.spots.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Glass(
                  onTap: () => showGlassSheet(context, (_) => SpotSheet(point: s.p, saved: s)),
                  child: Row(children: [
                    StatusDot(C.status(ShootStatusX.parse(s.status))),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                          '${s.name}${_me == null ? '' : ' · ${Geo.fmtDist(Geo.distance(_me!, s.p))}'}',
                          style: const TextStyle(fontSize: 19)),
                    ),
                    if (s.rating > 0) Text('★' * s.rating, style: const TextStyle(color: C.amber)),
                  ]),
                ),
              ),
          ],
          const SizedBox(height: 12),
          const Text('Land: USGS PAD-US · Map: OpenFreeMap © OpenStreetMap · Weather: NWS',
              style: TextStyle(fontSize: 13, color: C.text3)),
        ]),
      ),
    );
  }

  Widget _modeCard(String label, IconData icon, Color color, VoidCallback onTap) => Glass(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      );
}

// ───────────────────────────── Trips ─────────────────────────────

class TripsTab extends StatefulWidget {
  const TripsTab({super.key});
  @override
  State<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<TripsTab> {
  @override
  void initState() {
    super.initState();
    Store.instance.addListener(_r);
  }

  @override
  void dispose() {
    Store.instance.removeListener(_r);
    super.dispose();
  }

  void _r() => mounted ? setState(() {}) : null;

  Future<void> _paste() async {
    final clip = await Clipboard.getData('text/plain');
    final ctl = TextEditingController(text: clip?.text?.contains('=') == true ? clip!.text : '');
    if (!mounted) return;
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.slate,
        title: const Text('Open a link'),
        content: TextField(controller: ctl, maxLines: 3, decoration: const InputDecoration(hintText: 'Paste an outing or reply link')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Open')),
        ],
      ),
    );
    if (v == null) return;
    final msg = await importLinkText(v);
    if (mounted) toast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 30, 20, 120), children: [
        const Text('Trips', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: PrimaryButton('New outing', icon: Icons.group_add_rounded, onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OutingEditor()));
            }),
          ),
          const SizedBox(width: 10),
          GlassButton('Link', icon: Icons.add_link_rounded, onPressed: _paste),
        ]),
        const SectionTitle('Outings'),
        if (s.outings.isEmpty)
          const Text('Plan a group outing and share a link. Friends answer from any phone, no app needed.',
              style: TextStyle(fontSize: 17, color: C.text2)),
        for (final o in s.outings)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Glass(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OutingDetail(outingId: o.id))),
              child: Row(children: [
                Icon(o.lockedSlot != null ? Icons.lock_rounded : Icons.event_note_rounded,
                    color: o.lockedSlot != null ? C.sage : C.text2),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    Text(
                      o.lockedSlot != null
                          ? '${fmtDay(o.slots[o.lockedSlot!])} · ${fmtTime(o.slots[o.lockedSlot!])} · ${o.placeName}'
                          : '${o.slots.length} time options · ${o.responses.length} replies',
                      style: const TextStyle(fontSize: 16, color: C.text2),
                    ),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: C.text2),
              ]),
            ),
          ),
        const SectionTitle('Past trips'),
        if (s.trips.isEmpty)
          const Text('Navigate to a spot and your trip (track, time, rating) is saved here, on this device only.',
              style: TextStyle(fontSize: 17, color: C.text2)),
        for (final t in s.trips)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Dismissible(
              key: ValueKey(t.id),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => s.removeTrip(t.id),
              background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete_outline_rounded, color: C.red)),
              child: Glass(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => t.end == null
                        ? NavigateScreen(dest: t.dest, destName: t.title, resume: t)
                        : WrapupScreen(trip: t))),
                child: Row(children: [
                  const Icon(Icons.route_rounded, color: C.burgundyHi),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                      Text('${fmtDay(t.start)} · ${Geo.fmtMiles(t.distanceM)} · ${Geo.fmtDuration(t.duration)}'
                          '${t.end == null ? ' · in progress' : ''}',
                          style: const TextStyle(fontSize: 16, color: C.text2)),
                    ]),
                  ),
                  if (t.rating > 0) Text('★' * t.rating, style: const TextStyle(color: C.amber)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

// ───────────────────────────── Saved ─────────────────────────────

class SavedTab extends StatefulWidget {
  const SavedTab({super.key});
  @override
  State<SavedTab> createState() => _SavedTabState();
}

class _SavedTabState extends State<SavedTab> {
  @override
  void initState() {
    super.initState();
    Store.instance.addListener(_r);
  }

  @override
  void dispose() {
    Store.instance.removeListener(_r);
    super.dispose();
  }

  void _r() => mounted ? setState(() {}) : null;

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final me = LocationService.instance.last;
    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 30, 20, 120), children: [
        const Text('Saved', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Stored on this device only.', style: TextStyle(fontSize: 16, color: C.text3)),
        const SizedBox(height: 12),
        if (s.spots.isEmpty)
          const Text('Tap anywhere on the map and choose Save to keep a spot here.', style: TextStyle(fontSize: 17, color: C.text2)),
        for (final sp in s.spots)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Dismissible(
              key: ValueKey(sp.id),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => s.removeSpot(sp.id),
              background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete_outline_rounded, color: C.red)),
              child: Glass(
                onTap: () => showGlassSheet(context, (_) => SpotSheet(point: sp.p, saved: sp)),
                child: Row(children: [
                  StatusDot(C.status(ShootStatusX.parse(sp.status))),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(sp.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      Text(
                        [
                          if (me != null) Geo.fmtDist(Geo.distance(me, sp.p)),
                          if (sp.manager.isNotEmpty) sp.manager,
                          if (sp.visits > 0) '${sp.visits} visit${sp.visits == 1 ? '' : 's'}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 16, color: C.text2),
                      ),
                      if (sp.note.isNotEmpty)
                        Text('"${sp.note}"', style: const TextStyle(fontSize: 15, color: C.text3, fontStyle: FontStyle.italic)),
                    ]),
                  ),
                  if (sp.rating > 0) Text('★' * sp.rating, style: const TextStyle(color: C.amber, fontSize: 16)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

// ───────────────────────────── Profile ─────────────────────────────

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late final _name = TextEditingController(text: Store.instance.userName);
  List<ml.OfflineRegion> _regions = [];

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      ml.getListOfRegions().then((r) {
        if (mounted) setState(() => _regions = r);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget link(String t, String u) => ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t, style: const TextStyle(fontSize: 17)),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: C.text3),
          onTap: () => Handoff.url(u),
        );
    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 30, 20, 120), children: [
        const Text('Profile', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        TextField(
          controller: _name,
          style: const TextStyle(fontSize: 19),
          decoration: const InputDecoration(hintText: 'Your first name'),
          onSubmitted: (v) => Store.instance.setUserName(v),
          onChanged: (v) => Store.instance.setUserName(v),
        ),
        const SizedBox(height: 6),
        const Text('Used for your greeting and as the organizer name on outings. Kept on this device.',
            style: TextStyle(fontSize: 14, color: C.text3)),
        const SectionTitle('Outing sharing'),
        Glass(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(BackendService.instance.label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              BackendService.instance.syncsReplies
                  ? 'Replies sync through a free Supabase project.'
                  : 'No account or server. Outings travel inside links, and friends send back a reply link.',
              style: const TextStyle(fontSize: 16, color: C.text2),
            ),
          ]),
        ),
        if (!kIsWeb) ...[
          const SectionTitle('Offline areas'),
          if (_regions.isEmpty)
            const Text('None yet. On the map, tap the download button to save the area on screen.',
                style: TextStyle(fontSize: 16, color: C.text2)),
          for (final r in _regions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text((r.metadata['name'] as String?) ?? 'Area ${r.id}', style: const TextStyle(fontSize: 17)),
              subtitle: Text(
                  '${r.definition.bounds.southwest.latitude.toStringAsFixed(2)}, ${r.definition.bounds.southwest.longitude.toStringAsFixed(2)}',
                  style: const TextStyle(color: C.text3)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  await ml.deleteOfflineRegion(r.id);
                  final list = await ml.getListOfRegions();
                  if (mounted) setState(() => _regions = list);
                },
              ),
            ),
        ],
        const SectionTitle('Data sources'),
        link('Public land: USGS PAD-US 4.1 (public domain)', 'https://www.usgs.gov/programs/gap-analysis-project/science/pad-us-data-overview'),
        link('Map, roads & trails: © OpenStreetMap contributors (ODbL)', 'https://www.openstreetmap.org/copyright'),
        link('Basemap tiles: OpenFreeMap', 'https://openfreemap.org'),
        link('Weather & alerts: National Weather Service', 'https://www.weather.gov/documentation/services-web-api'),
        link('Elevation: Open-Meteo (CC BY 4.0)', 'https://open-meteo.com/en/docs/elevation-api'),
        link('Search: Photon by komoot', 'https://photon.komoot.io'),
        link('Drive times: OSRM demo server', 'https://project-osrm.org'),
        const SectionTitle('Important'),
        const Text(
          'Shooting status is a guide, not legal advice. Land lines, closures and fire orders change. Always verify posted signs, '
          'fire restrictions and local orders, follow state and county law, and know your target and what is beyond it.',
          style: TextStyle(fontSize: 16, color: C.text2, height: 1.4),
        ),
        const SizedBox(height: 16),
        Text('Public Land v1.0 · ${kIsWeb ? 'Web app' : 'Android'}', style: const TextStyle(fontSize: 14, color: C.text3)),
      ]),
    );
  }
}

/// Used by deep links / tests to open the map directly.
Widget mapAt(LL p) => MapScreen(center: p);

LL llOf(ml.LatLng p) => toLL(p);
