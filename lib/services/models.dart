import 'dart:convert';
import 'dart:math' as math;

import 'geo.dart';

String newId() {
  final r = math.Random();
  return List.generate(10, (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[r.nextInt(32)]).join();
}

class SavedSpot {
  final String id;
  String name;
  final LL p;
  String manager;
  String status;
  String note;
  int rating;
  final DateTime savedAt;
  int visits;
  SavedSpot({
    required this.id,
    required this.name,
    required this.p,
    this.manager = '',
    this.status = 'unknown',
    this.note = '',
    this.rating = 0,
    DateTime? savedAt,
    this.visits = 0,
  }) : savedAt = savedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'p': p.toJson(),
        'manager': manager,
        'status': status,
        'note': note,
        'rating': rating,
        'savedAt': savedAt.toIso8601String(),
        'visits': visits,
      };
  factory SavedSpot.fromJson(Map<String, dynamic> j) => SavedSpot(
        id: j['id'] as String,
        name: j['name'] as String,
        p: LL.fromJson((j['p'] as Map).cast<String, dynamic>()),
        manager: (j['manager'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'unknown',
        note: (j['note'] as String?) ?? '',
        rating: (j['rating'] as int?) ?? 0,
        savedAt: DateTime.tryParse((j['savedAt'] as String?) ?? ''),
        visits: (j['visits'] as int?) ?? 0,
      );
}

class Trip {
  final String id;
  String title;
  final LL dest;
  final DateTime start;
  DateTime? end;
  final List<LL> track;
  int rating;
  String note;
  String? spotId;
  String activity;
  Trip({
    required this.id,
    required this.title,
    required this.dest,
    required this.start,
    this.end,
    List<LL>? track,
    this.rating = 0,
    this.note = '',
    this.spotId,
    this.activity = 'shoot',
  }) : track = track ?? [];

  double get distanceM => Geo.lineLength(track);
  Duration get duration => (end ?? DateTime.now()).difference(start);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dest': dest.toJson(),
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
        'track': [for (final p in track) [double.parse(p.lat.toStringAsFixed(5)), double.parse(p.lon.toStringAsFixed(5))]],
        'rating': rating,
        'note': note,
        'spotId': spotId,
        'activity': activity,
      };
  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        title: j['title'] as String,
        dest: LL.fromJson((j['dest'] as Map).cast<String, dynamic>()),
        start: DateTime.parse(j['start'] as String),
        end: j['end'] == null ? null : DateTime.parse(j['end'] as String),
        track: [for (final c in (j['track'] as List? ?? [])) LL(((c as List)[0] as num).toDouble(), (c[1] as num).toDouble())],
        rating: (j['rating'] as int?) ?? 0,
        note: (j['note'] as String?) ?? '',
        spotId: j['spotId'] as String?,
        activity: (j['activity'] as String?) ?? 'shoot',
      );
}

/// A friend's answer to an outing.
class OutingResponse {
  final String name;
  final String activity; // hike | shoot | both
  final List<int> slots; // indices into outing.slots
  final List<String> gear; // gear items they'll bring
  final DateTime at;
  OutingResponse(this.name, this.activity, this.slots, this.gear, DateTime? at) : at = at ?? DateTime.now();

  Map<String, dynamic> toJson() => {'n': name, 'a': activity, 's': slots, 'g': gear, 't': at.millisecondsSinceEpoch ~/ 1000};
  factory OutingResponse.fromJson(Map<String, dynamic> j) => OutingResponse(
        j['n'] as String,
        (j['a'] as String?) ?? 'both',
        (j['s'] as List? ?? []).cast<int>(),
        (j['g'] as List? ?? []).cast<String>(),
        j['t'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['t'] as int) * 1000),
      );
}

/// Outing details. Only what friends need: never anyone's live location.
class Outing {
  final String id;
  String title;
  String placeName;
  LL? place; // the meetup / spot pin chosen by the organizer
  String? trailName;
  String activity;
  List<DateTime> slots;
  int durationH;
  String organizer;
  Map<String, String> gear; // item -> assigned friend name ('' = unassigned)
  List<OutingResponse> responses;
  int? lockedSlot;
  final DateTime createdAt;

  Outing({
    required this.id,
    required this.title,
    required this.placeName,
    this.place,
    this.trailName,
    this.activity = 'both',
    List<DateTime>? slots,
    this.durationH = 4,
    this.organizer = '',
    Map<String, String>? gear,
    List<OutingResponse>? responses,
    this.lockedSlot,
    DateTime? createdAt,
  })  : slots = slots ?? [],
        gear = gear ?? {},
        responses = responses ?? [],
        createdAt = createdAt ?? DateTime.now();

  /// Compact form used in share links.
  Map<String, dynamic> toShare() => {
        'v': 1,
        'i': id,
        't': title,
        'pn': placeName,
        if (place != null) 'p': [double.parse(place!.lat.toStringAsFixed(5)), double.parse(place!.lon.toStringAsFixed(5))],
        if (trailName != null) 'tr': trailName,
        'a': activity,
        's': [for (final s in slots) s.toUtc().millisecondsSinceEpoch ~/ 60000],
        'd': durationH,
        'o': organizer,
        if (gear.isNotEmpty) 'g': gear,
        if (lockedSlot != null) 'l': lockedSlot,
      };

  factory Outing.fromShare(Map<String, dynamic> j) => Outing(
        id: j['i'] as String,
        title: (j['t'] as String?) ?? 'Outing',
        placeName: (j['pn'] as String?) ?? '',
        place: j['p'] == null ? null : LL(((j['p'] as List)[0] as num).toDouble(), ((j['p'] as List)[1] as num).toDouble()),
        trailName: j['tr'] as String?,
        activity: (j['a'] as String?) ?? 'both',
        slots: [
          for (final m in (j['s'] as List? ?? []))
            DateTime.fromMillisecondsSinceEpoch((m as int) * 60000, isUtc: true).toLocal()
        ],
        durationH: (j['d'] as int?) ?? 4,
        organizer: (j['o'] as String?) ?? '',
        gear: ((j['g'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, (v as String?) ?? '')),
        lockedSlot: j['l'] as int?,
      );

  Map<String, dynamic> toJson() => {...toShare(), 'r': [for (final r in responses) r.toJson()], 'c': createdAt.toIso8601String()};
  factory Outing.fromJson(Map<String, dynamic> j) {
    final o = Outing.fromShare(j);
    o.responses = [for (final r in (j['r'] as List? ?? [])) OutingResponse.fromJson((r as Map).cast<String, dynamic>())];
    return o;
  }

  void upsertResponse(OutingResponse r) {
    responses.removeWhere((x) => x.name.trim().toLowerCase() == r.name.trim().toLowerCase());
    responses.add(r);
    for (final g in r.gear) {
      if (gear.containsKey(g)) gear[g] = r.name;
    }
  }

  int freeCount(int slot) => responses.where((r) => r.slots.contains(slot)).length + (organizer.isEmpty ? 0 : 1);
}

/// base64url(JSON) codec for links. No server needed.
class LinkCodec {
  static String encode(Map<String, dynamic> j) => base64Url.encode(utf8.encode(jsonEncode(j))).replaceAll('=', '');
  static Map<String, dynamic> decode(String s) {
    var t = s.trim();
    while (t.length % 4 != 0) {
      t += '=';
    }
    return (jsonDecode(utf8.decode(base64Url.decode(t))) as Map).cast<String, dynamic>();
  }
}
