import 'package:flutter/material.dart';

import '../services/geo.dart';
import '../services/land_service.dart';
import '../services/models.dart';
import '../services/osm_service.dart';
import '../services/pack_list.dart';
import '../services/store.dart';
import '../services/weather_service.dart';
import '../widgets/glass.dart';

/// Smart pack list: activity + forecast + wind/red flag + remoteness.
class PackScreen extends StatefulWidget {
  final String listId;
  final String activity;
  final LL? at;
  final DateTime? when;
  final Outing? outing;
  const PackScreen({super.key, required this.listId, required this.activity, this.at, this.when, this.outing});
  @override
  State<PackScreen> createState() => _PackScreenState();
}

class _PackScreenState extends State<PackScreen> {
  late Set<String> _checks;
  late String _activity = widget.activity;
  WeatherSnapshot? _wx;
  bool _remote = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checks = Store.instance.packChecks(widget.listId);
    _load();
  }

  Future<void> _load() async {
    final p = widget.at;
    if (p != null) {
      try {
        _wx = await WeatherService.instance.get(p);
      } catch (_) {}
      // Remoteness: few mapped buildings/roads within ~1.5 km, or far from you.
      final h = OsmService.instance.last;
      if (h != null && h.box.contains(p)) {
        final near = h.hazardPointsNear(p, 1500).length;
        _remote = h.pois.where((x) => Geo.distance(x.p, p) < 3000).length < 3 && near < 400;
      }
      final land = LandService.instance.statusAtLocal(p);
      if (land.parcel?.manager == 'BLM' && h == null) _remote = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  HourForecast? get _hour {
    final wx = _wx;
    if (wx == null) return null;
    return widget.when == null ? wx.now : (wx.at(widget.when!) ?? wx.now);
  }

  void _toggle(String id, bool on) {
    setState(() => on ? _checks.add(id) : _checks.remove(id));
    Store.instance.setPackChecks(widget.listId, _checks);
  }

  Future<void> _assign(PackItem it) async {
    final o = widget.outing;
    if (o == null) return;
    final names = <String>{if (o.organizer.isNotEmpty) o.organizer, ...o.responses.map((r) => r.name)}.toList();
    final ctl = TextEditingController(text: o.gear[it.label] ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.slate,
        title: Text('Who brings: ${it.label}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final n in names) ActionChip(label: Text(n), onPressed: () => Navigator.pop(ctx, n)),
          ]),
          const SizedBox(height: 12),
          TextField(controller: ctl, decoration: const InputDecoration(hintText: 'Name')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Unassign')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Assign')),
        ],
      ),
    );
    if (v == null) return;
    o.gear[it.label] = v;
    await Store.instance.upsertOuting(o);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final h = _hour;
    final items = buildPackList(PackInput(
      activity: _activity,
      tempF: h?.tempF,
      windMph: h?.windMph,
      redFlag: _wx?.redFlag ?? false,
      remote: _remote,
      precipPct: h?.precipPct ?? 0,
      groupSize: (widget.outing?.responses.length ?? 0) + 1,
    ));
    final done = items.where((i) => _checks.contains(i.id)).length;
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, size: 26)),
              const Expanded(child: Text('Pack list', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700))),
              Text('$done/${items.length}', style: const TextStyle(fontSize: 20, color: C.sage, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            PillSegments(
              labels: const ['Hike', 'Shoot', 'Both'],
              index: const ['hike', 'shoot', 'both'].indexOf(_activity).clamp(0, 2),
              onChanged: (i) => setState(() => _activity = const ['hike', 'shoot', 'both'][i]),
            ),
            const SizedBox(height: 12),
            Glass(
              child: _loading
                  ? const Text('Checking forecast…', style: TextStyle(fontSize: 17))
                  : Wrap(spacing: 8, runSpacing: 8, children: [
                      if (h != null) Chip2('${h.tempF}°F · ${h.short}', icon: Icons.thermostat_rounded),
                      if (h != null) Chip2('${h.windMph.round()} mph wind', icon: Icons.air_rounded),
                      if (_wx?.redFlag == true) const Chip2('Red Flag', color: C.red, icon: Icons.local_fire_department_rounded),
                      if (_remote) const Chip2('Remote', color: C.amber, icon: Icons.terrain_rounded),
                      if (h == null) const Chip2('No forecast (NWS covers the US only)'),
                    ]),
            ),
            for (final sec in packSections)
              if (items.any((i) => i.section == sec)) ...[
                SectionTitle(sec),
                Glass(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    for (final it in items.where((i) => i.section == sec))
                      CheckboxListTile(
                        value: _checks.contains(it.id),
                        onChanged: (v) => _toggle(it.id, v == true),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(it.label, style: const TextStyle(fontSize: 18)),
                        subtitle: it.why == null ? null : Text(it.why!, style: const TextStyle(fontSize: 14, color: C.text3)),
                        secondary: sec == 'Group gear' && widget.outing != null
                            ? TextButton(
                                onPressed: () => _assign(it),
                                child: Text(
                                  (widget.outing!.gear[it.label] ?? '').isEmpty ? 'Assign' : widget.outing!.gear[it.label]!,
                                  style: const TextStyle(fontSize: 16, color: C.sage),
                                ),
                              )
                            : null,
                      ),
                  ]),
                ),
              ],
            const SizedBox(height: 14),
            if (widget.outing != null)
              const Text('Group gear assignments ride along in the outing link when you share it.',
                  style: TextStyle(fontSize: 14, color: C.text3)),
          ]),
        ),
      ),
    );
  }
}
