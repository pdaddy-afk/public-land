import 'package:flutter/material.dart';

import '../services/geo.dart';
import '../services/handoff.dart';
import '../services/models.dart';
import '../services/store.dart';
import '../widgets/glass.dart';

/// Wrap up: stats, pack-out checklist, rating + note saved to the spot, share recap.
class WrapupScreen extends StatefulWidget {
  final Trip trip;
  const WrapupScreen({super.key, required this.trip});
  @override
  State<WrapupScreen> createState() => _WrapupScreenState();
}

class _WrapupScreenState extends State<WrapupScreen> {
  static const packOut = [
    ('brass', 'Brass and shell casings picked up'),
    ('targets', 'Targets, stands and staples removed'),
    ('trash', 'All trash packed out (and any you found)'),
    ('glass', 'No glass, clay shards or debris left'),
    ('fire', 'No smoldering spots; area cool'),
  ];
  late Set<String> _checks;
  late int _rating = widget.trip.rating;
  late final _note = TextEditingController(text: widget.trip.note);

  @override
  void initState() {
    super.initState();
    widget.trip.end ??= DateTime.now();
    _checks = Store.instance.packChecks('packout:${widget.trip.id}');
  }

  Future<void> _finish() async {
    final t = widget.trip;
    t.rating = _rating;
    t.note = _note.text.trim();
    await Store.instance.upsertTrip(t);
    // Save rating + note to the spot (create one if needed).
    var spot = t.spotId == null ? null : Store.instance.spots.where((s) => s.id == t.spotId).firstOrNull;
    spot ??= Store.instance.spotNear(t.dest.lat, t.dest.lon);
    spot ??= SavedSpot(id: newId(), name: t.title, p: t.dest);
    spot.rating = _rating;
    if (t.note.isNotEmpty) spot.note = t.note;
    spot.visits += 1;
    t.spotId = spot.id;
    await Store.instance.upsertSpot(spot);
    await Store.instance.upsertTrip(t);
    if (mounted) {
      toast(context, 'Saved to "${spot.name}"');
      Navigator.pop(context);
    }
  }

  Future<void> _share() async {
    final t = widget.trip;
    final stars = '★' * _rating + '☆' * (5 - _rating);
    final text = 'Public Land recap: ${t.title}\n'
        '${fmtDay(t.start)} · ${Geo.fmtMiles(t.distanceM)} · ${Geo.fmtDuration(t.duration)}\n'
        '$stars${_note.text.trim().isEmpty ? '' : '\n"${_note.text.trim()}"'}\n'
        'Packed out: ${_checks.length}/${packOut.length} ✓';
    final ok = await ShareHelper.text(text, subject: 'Trip recap');
    if (!ok && mounted) toast(context, 'Recap copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, size: 26)),
              const SizedBox(width: 4),
              const Text('Wrap up', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
            ]),
            Text(t.title, style: const TextStyle(fontSize: 19, color: C.text2)),
            const SizedBox(height: 16),
            Glass(
              child: Row(children: [
                _stat('Distance', Geo.fmtMiles(t.distanceM)),
                _stat('Time', Geo.fmtDuration(t.duration)),
                _stat('Points', '${t.track.length}'),
              ]),
            ),
            const SectionTitle('Pack-out check'),
            Glass(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                for (final (id, label) in packOut)
                  CheckboxListTile(
                    value: _checks.contains(id),
                    onChanged: (v) {
                      setState(() => v == true ? _checks.add(id) : _checks.remove(id));
                      Store.instance.setPackChecks('packout:${t.id}', _checks);
                    },
                    title: Text(label, style: const TextStyle(fontSize: 18)),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
              ]),
            ),
            const SectionTitle('Rate this spot'),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 44,
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: i <= _rating ? C.amber : C.text3),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLines: 3,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(hintText: 'Note for next time (road condition, best backstop…)'),
            ),
            const SizedBox(height: 20),
            PrimaryButton('Save to spot', icon: Icons.bookmark_added_rounded, onPressed: _finish),
            const SizedBox(height: 10),
            GlassButton('Share recap', icon: Icons.ios_share_rounded, onPressed: _share),
            const SizedBox(height: 10),
            const Text('Recaps never include your track or live location.', style: TextStyle(fontSize: 14, color: C.text3)),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String k, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 15, color: C.text3)),
          Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ]),
      );
}
