import 'package:flutter/material.dart';

import '../services/clearance.dart';
import '../services/geo.dart';
import '../services/handoff.dart';
import '../services/land_service.dart';
import '../services/models.dart';
import '../services/places_service.dart';
import '../services/store.dart';
import '../widgets/glass.dart';
import 'navigate_screen.dart';
import 'outing_screens.dart';

/// Spot detail card: land manager, status, rules, source, distance, actions.
class SpotSheet extends StatefulWidget {
  final LL point;
  final String? name;
  final SavedSpot? saved;
  const SpotSheet({super.key, required this.point, this.name, this.saved});
  @override
  State<SpotSheet> createState() => _SpotSheetState();
}

class _SpotSheetState extends State<SpotSheet> {
  Clearance? _c;
  String? _err;
  ({double meters, Duration time, bool estimated})? _drive;
  bool _rulesOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await ClearanceService.evaluate(widget.point);
      if (mounted) setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _err = 'Could not load land status: $e');
    }
    final me = LocationService.instance.last ?? await LocationService.instance.current();
    if (me != null) {
      final d = await RoutingService.drive(me, widget.point);
      if (mounted) setState(() => _drive = d);
    }
  }

  String get _title {
    if (widget.saved != null) return widget.saved!.name;
    if (widget.name != null) return widget.name!;
    final c = _c;
    if (c?.land.parcel != null) return c!.land.unitName;
    return 'Dropped pin';
  }

  Future<void> _save() async {
    final c = _c;
    final existing = widget.saved ?? Store.instance.spotNear(widget.point.lat, widget.point.lon);
    final ctl = TextEditingController(text: existing?.name ?? _title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.slate,
        title: const Text('Save spot'),
        content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final s = existing ??
        SavedSpot(id: newId(), name: name, p: widget.point);
    s.name = name;
    s.manager = c?.land.parcel == null ? '' : '${c!.land.info.code} · ${c.land.unitName}';
    s.status = c?.clear == true ? 'allowed' : (c?.land.status.name ?? 'unknown');
    await Store.instance.upsertSpot(s);
    if (mounted) toast(context, 'Saved "$name" on this device');
  }

  void _navigate() {
    showGlassSheet(context, (ctx) => NavChooser(dest: widget.point, label: _title));
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(_title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(widget.point.toString(), style: const TextStyle(fontSize: 15, color: C.text3)),
        const SizedBox(height: 14),
        if (_err != null) Text(_err!, style: const TextStyle(color: C.amber, fontSize: 16)),
        if (c == null && _err == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: C.sage))),
        if (c != null) ...[
          Glass(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                StatusDot(c.clear ? C.sage : C.status(c.land.status == ShootStatus.allowed ? ShootStatus.restricted : c.land.status),
                    size: 14),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(c.clear ? 'Clear to shoot here' : 'Not clear to shoot here',
                      style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: c.clear ? C.sage : (c.land.status == ShootStatus.allowed ? C.rose : C.status(c.land.status)))),
                ),
              ]),
              const SizedBox(height: 8),
              for (final r in c.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $r', style: const TextStyle(fontSize: 16, color: C.text2)),
                ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip2(c.land.status.label, color: C.status(c.land.status)),
                if (c.land.checkLocalOrders && c.land.parcel != null)
                  const Chip2('Check local orders', color: C.amber, icon: Icons.info_outline_rounded),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          _kv('Land manager', c.land.managerName),
          _kv('Unit', c.land.unitName),
          if (c.hazardsLoaded) ...[
            _kv('Nearest trail', Geo.fmtDist(c.trailM)),
            _kv('Nearest road / track', Geo.fmtDist(c.roadM)),
            _kv('Nearest building / camp', Geo.fmtDist(c.structM)),
          ],
          if (_drive != null)
            _kv('From you', '${Geo.fmtMiles(_drive!.meters)} · ${_drive!.estimated ? '~' : ''}${Geo.fmtDuration(_drive!.time)} drive'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _rulesOpen = !_rulesOpen),
            child: Row(children: [
              const Text('Rules', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              Icon(_rulesOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: C.text2),
            ]),
          ),
          if (_rulesOpen) ...[
            const SizedBox(height: 6),
            Text(c.land.rulesText, style: const TextStyle(fontSize: 16, color: C.text2, height: 1.4)),
          ],
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => Handoff.url(c.land.sourceUrl),
            icon: const Icon(Icons.open_in_new_rounded, size: 18, color: C.sage),
            label: const Text('Source / order', style: TextStyle(color: C.sage, fontSize: 16)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: PrimaryButton('Navigate', icon: Icons.navigation_rounded, onPressed: _navigate)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: GlassButton('Save', icon: Icons.bookmark_add_outlined, onPressed: _save)),
            const SizedBox(width: 10),
            Expanded(
              child: GlassButton('Plan outing', icon: Icons.group_add_outlined, onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(
                    builder: (_) => OutingEditor(placeName: _title, place: widget.point)));
              }),
            ),
          ]),
          const SizedBox(height: 10),
          const Text('A guide only. Always verify posted signs and local orders.',
              style: TextStyle(fontSize: 14, color: C.text3)),
        ],
      ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(k, style: const TextStyle(fontSize: 16, color: C.text3))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 17))),
        ]),
      );
}

/// Pick how to navigate: in-app follow-me, or hand off to a maps app (free).
class NavChooser extends StatelessWidget {
  final LL dest;
  final String label;
  const NavChooser({super.key, required this.dest, required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Navigate to $label', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 14),
      PrimaryButton('Follow me in Public Land', icon: Icons.route_rounded, onPressed: () {
        final nav = Navigator.of(context);
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => NavigateScreen(dest: dest, destName: label)));
      }),
      const SizedBox(height: 10),
      GlassButton('Google Maps', icon: Icons.map_outlined, onPressed: () => Handoff.googleMaps(dest)),
      const SizedBox(height: 10),
      GlassButton('Apple Maps', icon: Icons.map_rounded, onPressed: () => Handoff.appleMaps(dest)),
      if (Handoff.isAndroid) ...[
        const SizedBox(height: 10),
        GlassButton('Other app (geo:)', icon: Icons.open_in_new_rounded, onPressed: () => Handoff.geoIntent(dest, label)),
      ],
      const SizedBox(height: 10),
      const Text('Maps apps route on public roads. The last stretch on dirt may not be routable.',
          style: TextStyle(fontSize: 14, color: C.text3)),
    ]);
  }
}
