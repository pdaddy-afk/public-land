import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/backend_service.dart';
import '../services/geo.dart';
import '../services/handoff.dart';
import '../services/models.dart';
import '../services/pack_list.dart';
import '../services/planner.dart';
import '../services/store.dart';
import '../services/weather_service.dart';
import '../widgets/glass.dart';
import 'pack_screen.dart';

const _acts = ['hike', 'shoot', 'both'];

/// Create / edit an outing: place, activity, candidate time slots.
class OutingEditor extends StatefulWidget {
  final String? placeName;
  final LL? place;
  final String? trailName;
  final Outing? existing;
  const OutingEditor({super.key, this.placeName, this.place, this.trailName, this.existing});
  @override
  State<OutingEditor> createState() => _OutingEditorState();
}

class _OutingEditorState extends State<OutingEditor> {
  late final _title = TextEditingController(text: widget.existing?.title ?? 'Saturday Outing');
  late final _place = TextEditingController(text: widget.existing?.placeName ?? widget.placeName ?? '');
  late final _name = TextEditingController(text: widget.existing?.organizer ?? Store.instance.userName);
  late String _act = widget.existing?.activity ?? 'both';
  late int _dur = widget.existing?.durationH ?? 4;
  late List<DateTime> _slots = List.of(widget.existing?.slots ?? _suggest());

  static List<DateTime> _suggest() {
    final now = DateTime.now();
    DateTime next(int weekday) {
      var d = DateTime(now.year, now.month, now.day, 7, 30);
      while (d.weekday != weekday || d.isBefore(now)) {
        d = d.add(const Duration(days: 1));
      }
      return d;
    }

    final sat = next(DateTime.saturday), sun = next(DateTime.sunday);
    return [sat, DateTime(sat.year, sat.month, sat.day, 13), sun];
  }

  Future<void> _addSlot() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, firstDate: now, lastDate: now.add(const Duration(days: 60)), initialDate: now.add(const Duration(days: 1)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 7, minute: 30));
    if (t == null) return;
    setState(() => _slots = [..._slots, DateTime(d.year, d.month, d.day, t.hour, t.minute)]..sort());
  }

  Future<void> _save() async {
    if (_slots.isEmpty) {
      toast(context, 'Add at least one time slot');
      return;
    }
    final organizer = _name.text.trim();
    if (organizer.isNotEmpty && Store.instance.userName.isEmpty) await Store.instance.setUserName(organizer);
    final o = widget.existing ??
        Outing(id: newId(), title: '', placeName: '', place: widget.place, trailName: widget.trailName);
    o.title = _title.text.trim().isEmpty ? 'Outing' : _title.text.trim();
    o.placeName = _place.text.trim();
    o.activity = _act;
    o.durationH = _dur;
    o.slots = _slots;
    o.organizer = organizer;
    // Group gear friends can claim.
    for (final it in buildPackList(PackInput(activity: _act)).where((i) => i.section == 'Group gear')) {
      o.gear.putIfAbsent(it.label, () => '');
    }
    await Store.instance.upsertOuting(o);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OutingDetail(outingId: o.id)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, size: 26)),
              const Text('Plan an outing', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 14),
            TextField(controller: _title, style: const TextStyle(fontSize: 19), decoration: const InputDecoration(hintText: 'Title')),
            const SizedBox(height: 10),
            TextField(
                controller: _place,
                style: const TextStyle(fontSize: 19),
                decoration: const InputDecoration(hintText: 'Spot or meetup name')),
            if (widget.place != null || widget.existing?.place != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 8),
                child: Text('Pin: ${(widget.place ?? widget.existing!.place)!}', style: const TextStyle(color: C.text3)),
              ),
            const SizedBox(height: 10),
            TextField(
                controller: _name,
                style: const TextStyle(fontSize: 19),
                decoration: const InputDecoration(hintText: 'Your first name (shown to friends)')),
            const SectionTitle('Activity'),
            PillSegments(
                labels: const ['Hike', 'Shoot', 'Both'],
                index: _acts.indexOf(_act),
                onChanged: (i) => setState(() => _act = _acts[i])),
            SectionTitle('Time options', trailing: TextButton.icon(onPressed: _addSlot, icon: const Icon(Icons.add), label: const Text('Add'))),
            for (var i = 0; i < _slots.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Glass(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(children: [
                    Expanded(
                        child: Text('${fmtDay(_slots[i])} · ${fmtTime(_slots[i])}', style: const TextStyle(fontSize: 18))),
                    IconButton(
                        onPressed: () => setState(() => _slots = List.of(_slots)..removeAt(i)),
                        icon: const Icon(Icons.close_rounded, color: C.text2)),
                  ]),
                ),
              ),
            const SectionTitle('How long'),
            Row(children: [
              for (final h in [2, 3, 4, 6, 8])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$h h', style: const TextStyle(fontSize: 16)),
                    selected: _dur == h,
                    selectedColor: C.burgundy,
                    onSelected: (_) => setState(() => _dur = h),
                  ),
                ),
            ]),
            const SizedBox(height: 24),
            PrimaryButton('Create outing', icon: Icons.check_rounded, onPressed: _save),
            const SizedBox(height: 10),
            const Text('Links carry only the outing details (place, times, gear). Never anyone\'s live location.',
                style: TextStyle(fontSize: 14, color: C.text3)),
          ]),
        ),
      ),
    );
  }
}

/// Organizer view: who's free, best time (scored with NWS), share, lock in.
class OutingDetail extends StatefulWidget {
  final String outingId;
  const OutingDetail({super.key, required this.outingId});
  @override
  State<OutingDetail> createState() => _OutingDetailState();
}

class _OutingDetailState extends State<OutingDetail> {
  WeatherSnapshot? _wx;
  bool _syncing = false;

  Outing? get _o => Store.instance.outing(widget.outingId);

  @override
  void initState() {
    super.initState();
    final o = _o;
    if (o?.place != null) {
      WeatherService.instance.get(o!.place!).then((w) {
        if (mounted) setState(() => _wx = w);
      }).catchError((_) {});
    }
    if (BackendService.instance.syncsReplies) _sync();
  }

  Future<void> _sync() async {
    final o = _o;
    if (o == null) return;
    setState(() => _syncing = true);
    try {
      final rs = await BackendService.instance.fetchResponses(o);
      for (final r in rs) {
        o.upsertResponse(r);
      }
      await Store.instance.upsertOuting(o);
    } catch (e) {
      if (mounted) toast(context, 'Could not refresh replies: $e');
    }
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _share() async {
    final o = _o!;
    final link = await BackendService.instance.outingLink(o);
    final text = '${o.organizer.isEmpty ? 'Join' : '${o.organizer} invited you:'} ${o.title}'
        '${o.placeName.isEmpty ? '' : ' at ${o.placeName}'} (${activityLabel(o.activity)}). '
        'Pick the times you\'re free (no app needed):\n$link';
    final ok = await ShareHelper.text(text, subject: o.title);
    if (!ok && mounted) toast(context, 'Invite link copied');
  }

  Future<void> _pasteReply() async {
    final ctl = TextEditingController();
    final clip = await Clipboard.getData('text/plain');
    if (clip?.text?.contains('r=') == true) ctl.text = clip!.text!;
    if (!mounted) return;
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.slate,
        title: const Text('Add a reply link'),
        content: TextField(controller: ctl, maxLines: 3, decoration: const InputDecoration(hintText: 'Paste the link a friend sent')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Add')),
        ],
      ),
    );
    if (v == null || !mounted) return;
    final msg = await importLinkText(v);
    if (mounted) {
      toast(context, msg);
      setState(() {});
    }
  }

  Future<void> _lock(int slot) async {
    final o = _o!;
    o.lockedSlot = slot;
    await Store.instance.upsertOuting(o);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    if (o == null) return const Scaffold(body: Center(child: Text('Outing not found')));
    final ranked = Planner.rank(o, _wx);
    final best = ranked.isEmpty ? null : ranked.first;
    final people = [if (o.organizer.isNotEmpty) o.organizer, ...o.responses.map((r) => r.name)];
    final locked = o.lockedSlot;
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _sync,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, size: 26)),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => OutingEditor(existing: o)))
                      .then((_) => setState(() {})),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () async {
                    await Store.instance.removeOuting(o.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ]),
              Text(o.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
              Text(
                [o.placeName, if (o.trailName != null) o.trailName!, activityLabel(o.activity)].where((s) => s.isNotEmpty).join(' · '),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: C.text2),
              ),
              const SizedBox(height: 16),
              // Slot grid
              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                for (var i = 0; i < o.slots.length; i++) _slotTile(o, i, best?.index == i, locked == i),
              ]),
              const SizedBox(height: 16),
              if (best != null)
                Glass(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(locked != null ? 'LOCKED IN' : 'BEST TIME',
                        style: const TextStyle(fontSize: 15, color: C.text3, letterSpacing: 1.2)),
                    () {
                      final s = locked != null ? ranked.firstWhere((r) => r.index == locked) : best;
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${fmtWeekday(s.start)} · ${fmtTime(s.start)}',
                            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700)),
                        Text('${fmtDay(s.start)} · ${s.free} of ${s.total} free',
                            style: const TextStyle(fontSize: 17, color: C.text2)),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          if (s.wx != null) Chip2('${s.wx!.tempF}° ${s.wx!.short}', icon: Icons.wb_sunny_outlined),
                          if (s.wx != null) Chip2('${s.wx!.windMph.round()} mph', icon: Icons.air_rounded),
                          s.redFlag
                              ? const Chip2('Red Flag: no shooting', color: C.red, icon: Icons.local_fire_department_rounded)
                              : Chip2(_wx == null ? 'Fire alerts: unknown' : 'No fire alerts',
                                  color: _wx == null ? C.text2 : C.sage, icon: Icons.local_fire_department_outlined),
                          for (final n in s.notes) Chip2(n, color: C.amber),
                        ]),
                      ]);
                    }(),
                  ]),
                ),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                for (final n in people) _avatar(n, o),
              ]),
              const SizedBox(height: 18),
              if (locked == null && best != null)
                PrimaryButton('Lock it in', icon: Icons.lock_rounded, onPressed: () => _lock(best.index))
              else if (locked != null) ...[
                PrimaryButton('Add to calendar (.ics)', icon: Icons.event_rounded, onPressed: () {
                  ShareHelper.ics(buildIcs(o, locked), '${o.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.ics');
                }),
                const SizedBox(height: 10),
                if (o.place != null)
                  GlassButton('Share meetup map link', icon: Icons.place_outlined, onPressed: () {
                    ShareHelper.text('${o.title} meetup: ${meetupMapLink(o.place!)}');
                  }),
                const SizedBox(height: 10),
                GlassButton('Unlock', icon: Icons.lock_open_rounded, onPressed: () async {
                  o.lockedSlot = null;
                  await Store.instance.upsertOuting(o);
                  setState(() {});
                }),
              ],
              const SizedBox(height: 10),
              GlassButton('Share invite link', icon: Icons.ios_share_rounded, onPressed: _share),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: BackendService.instance.syncsReplies
                      ? GlassButton(_syncing ? 'Refreshing…' : 'Refresh replies', icon: Icons.sync_rounded, onPressed: _sync)
                      : GlassButton('Add reply link', icon: Icons.add_link_rounded, onPressed: _pasteReply),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlassButton('Pack list', icon: Icons.checklist_rounded, onPressed: () {
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (_) => PackScreen(
                                listId: 'outing:${o.id}',
                                activity: o.activity,
                                at: o.place,
                                when: locked != null ? o.slots[locked] : best?.start,
                                outing: o)))
                        .then((_) => setState(() {}));
                  }),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                BackendService.instance.syncsReplies
                    ? 'Replies sync through your Supabase project.'
                    : 'Friends answer on the web page and send you a reply link. Open it here (or tap Add reply link).',
                style: const TextStyle(fontSize: 14, color: C.text3),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _slotTile(Outing o, int i, bool best, bool locked) {
    final s = o.slots[i];
    final free = o.freeCount(i);
    final total = o.responses.length + (o.organizer.isEmpty ? 0 : 1);
    final glow = best || locked;
    return GestureDetector(
      onTap: () => _lock(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 108,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: glow ? C.sageDeep.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: glow ? C.sage : Colors.white24, width: glow ? 2 : 1),
          boxShadow: glow ? [BoxShadow(color: C.sage.withValues(alpha: 0.4), blurRadius: 16)] : null,
        ),
        child: Column(children: [
          Text(fmtWeekday(s), style: const TextStyle(fontSize: 17, color: C.text2)),
          Text(fmtTime(s), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('$free/$total', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: glow ? Colors.white : C.text)),
        ]),
      ),
    );
  }

  Widget _avatar(String name, Outing o) {
    final r = o.responses.where((x) => x.name == name).firstOrNull;
    final ok = r == null || r.slots.isNotEmpty;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Column(children: [
      Stack(clipBehavior: Clip.none, children: [
        CircleAvatar(
            radius: 26,
            backgroundColor: C.slate,
            child: Text(initial, style: const TextStyle(fontSize: 22, color: C.text))),
        Positioned(
          right: -2,
          bottom: -2,
          child: CircleAvatar(
            radius: 10,
            backgroundColor: ok ? C.sageDeep : C.text3,
            child: Icon(ok ? Icons.check_rounded : Icons.remove_rounded, size: 14, color: Colors.white),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      Text(name, style: const TextStyle(fontSize: 14, color: C.text2)),
      if (r != null) Text(activityLabel(r.activity), style: const TextStyle(fontSize: 12, color: C.text3)),
    ]);
  }
}

/// Friend view (works in iPhone Safari with no app): pick free slots + activity + name.
class FriendRespondScreen extends StatefulWidget {
  final Outing outing;
  const FriendRespondScreen({super.key, required this.outing});
  @override
  State<FriendRespondScreen> createState() => _FriendRespondScreenState();
}

class _FriendRespondScreenState extends State<FriendRespondScreen> {
  final _name = TextEditingController();
  final Set<int> _slots = {};
  final Set<String> _gear = {};
  late String _act = widget.outing.activity;
  Uri? _reply;
  bool _sent = false;
  WeatherSnapshot? _wx;

  @override
  void initState() {
    super.initState();
    _name.text = Store.instance.userName;
    final p = widget.outing.place;
    if (p != null) {
      WeatherService.instance.get(p).then((w) {
        if (mounted) setState(() => _wx = w);
      }).catchError((_) {});
    }
  }

  Future<void> _send() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast(context, 'Add your name first');
      return;
    }
    await Store.instance.setUserName(name);
    final r = OutingResponse(name, _act, _slots.toList()..sort(), _gear.toList(), null);
    final link = await BackendService.instance.submitResponse(widget.outing, r);
    setState(() {
      _reply = link;
      _sent = true;
    });
    if (link != null) {
      final who = widget.outing.organizer.isEmpty ? '' : '${widget.outing.organizer}, ';
      final ok = await ShareHelper.text('$who${name.split(' ').first} replied to ${widget.outing.title}: $link',
          subject: 'Reply: ${widget.outing.title}');
      if (!ok && mounted) toast(context, 'Reply link copied. Paste it to the organizer.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.outing;
    final unclaimed = o.gear.entries.where((e) => e.value.isEmpty).map((e) => e.key).toList();
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(o.organizer.isEmpty ? "You're invited" : '${o.organizer} invited you',
                style: const TextStyle(fontSize: 18, color: C.text2)),
            Text(o.title, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
            Text([o.placeName, if (o.trailName != null) o.trailName!].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 18, color: C.text2)),
            if (o.place != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Handoff.url(meetupMapLink(o.place!)),
                  icon: const Icon(Icons.place_outlined, color: C.sage),
                  label: const Text('View meetup on map', style: TextStyle(color: C.sage, fontSize: 17)),
                ),
              ),
            if (_wx?.redFlag == true)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Chip2('Red Flag warning in effect: no shooting', color: C.red, icon: Icons.local_fire_department_rounded),
              ),
            const SectionTitle('I want to'),
            PillSegments(
                labels: const ['Hike', 'Shoot', 'Both'],
                index: _acts.indexOf(_act).clamp(0, 2),
                onChanged: (i) => setState(() => _act = _acts[i])),
            const SectionTitle("I'm free"),
            for (var i = 0; i < o.slots.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Glass(
                  padding: EdgeInsets.zero,
                  tint: _slots.contains(i) ? C.sage : null,
                  opacity: _slots.contains(i) ? 0.18 : 0.10,
                  onTap: () => setState(() => _slots.contains(i) ? _slots.remove(i) : _slots.add(i)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Icon(_slots.contains(i) ? Icons.check_circle_rounded : Icons.circle_outlined,
                          color: _slots.contains(i) ? C.sage : C.text3, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('${fmtDay(o.slots[i])} · ${fmtTime(o.slots[i])}', style: const TextStyle(fontSize: 19)),
                      ),
                      if (_wx?.at(o.slots[i]) != null)
                        Text('${_wx!.at(o.slots[i])!.tempF}°', style: const TextStyle(fontSize: 17, color: C.text2)),
                    ]),
                  ),
                ),
              ),
            if (unclaimed.isNotEmpty) ...[
              const SectionTitle("I'll bring"),
              Glass(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  for (final g in unclaimed)
                    CheckboxListTile(
                      value: _gear.contains(g),
                      onChanged: (v) => setState(() => v == true ? _gear.add(g) : _gear.remove(g)),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(g, style: const TextStyle(fontSize: 18)),
                    ),
                ]),
              ),
            ],
            const SectionTitle('Your name'),
            TextField(controller: _name, style: const TextStyle(fontSize: 19), decoration: const InputDecoration(hintText: 'First name')),
            const SizedBox(height: 22),
            PrimaryButton(_sent ? 'Send again' : 'Send my answer', icon: Icons.send_rounded, onPressed: _send),
            if (_sent && _reply == null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Sent! The organizer will see it.', style: TextStyle(fontSize: 17, color: C.sage)),
              ),
            if (_reply != null) ...[
              const SizedBox(height: 14),
              Glass(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Send this reply link to the organizer:', style: TextStyle(fontSize: 16, color: C.text2)),
                  const SizedBox(height: 6),
                  SelectableText(_reply.toString(), style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  GlassButton('Copy link', icon: Icons.copy_rounded, onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _reply.toString()));
                    if (context.mounted) toast(context, 'Copied');
                  }),
                ]),
              ),
            ],
            if (o.lockedSlot != null) ...[
              const SizedBox(height: 12),
              GlassButton('Add to calendar', icon: Icons.event_rounded,
                  onPressed: () => ShareHelper.ics(buildIcs(o, o.lockedSlot!), 'outing.ics')),
            ],
            const SizedBox(height: 18),
            const Text(
              'iPhone tip: tap Share → Add to Home Screen to keep Public Land like an app. Free, no account.',
              style: TextStyle(fontSize: 14, color: C.text3),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Parse a pasted/opened link. Returns a user-facing message.
Future<String> importLinkText(String text) async {
  final m = RegExp(r'[?&]([or])=([A-Za-z0-9_\-]+)').firstMatch(text);
  if (m == null) return 'That does not look like a Public Land link';
  try {
    final j = LinkCodec.decode(m.group(2)!);
    if (m.group(1) == 'r') return await importReply(j);
    final o = Outing.fromShare(j);
    final existing = Store.instance.outing(o.id);
    if (existing == null) {
      await Store.instance.upsertOuting(o);
      return 'Added outing "${o.title}"';
    }
    return 'You already have "${o.title}"';
  } catch (_) {
    return 'That link could not be read';
  }
}

Future<String> importReply(Map<String, dynamic> j) async {
  final o = Store.instance.outing(j['i'] as String);
  final r = OutingResponse.fromJson(j);
  if (o == null) {
    return 'Reply from ${r.name} is for "${j['t'] ?? 'an outing'}", which is not on this device. Open it where you created the outing.';
  }
  o.upsertResponse(r);
  await Store.instance.upsertOuting(o);
  return 'Added ${r.name}\'s reply to "${o.title}"';
}
