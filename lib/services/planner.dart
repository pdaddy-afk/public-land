import 'geo.dart';
import 'models.dart';
import 'weather_service.dart';

class SlotScore {
  final int index;
  final DateTime start;
  final int free;
  final int total;
  final double score;
  final HourForecast? wx;
  final bool daylight;
  final bool redFlag;
  final List<String> notes;
  SlotScore(this.index, this.start, this.free, this.total, this.score, this.wx, this.daylight, this.redFlag, this.notes);
}

/// Best time = most people free, then weather, daylight and fire alerts.
class Planner {
  static List<SlotScore> rank(Outing o, WeatherSnapshot? wx) {
    final total = o.responses.length + (o.organizer.isEmpty ? 0 : 1);
    final out = <SlotScore>[];
    for (var i = 0; i < o.slots.length; i++) {
      final s = o.slots[i];
      final free = o.freeCount(i);
      final notes = <String>[];
      var score = free * 100.0;
      final h = wx?.at(s);
      if (h != null) {
        final comfy = (h.tempF - 68).abs();
        score -= comfy * 0.8;
        score -= h.precipPct * 0.4;
        if (h.windMph > 15) {
          score -= (h.windMph - 15) * 2;
          notes.add('Windy');
        }
        if (h.tempF >= 95) notes.add('Hot');
        if (h.tempF <= 40) notes.add('Cold');
      } else {
        notes.add('Forecast not out yet');
      }
      var daylight = true;
      if (o.place != null) {
        final rise = Sun.sunrise(s, o.place!);
        final set = Sun.sunset(s, o.place!);
        final end = s.add(Duration(hours: o.durationH));
        if (rise != null && set != null) {
          daylight = !s.isBefore(rise.subtract(const Duration(minutes: 30))) && !end.isAfter(set);
          if (!daylight) {
            score -= 40;
            notes.add('Ends after sunset ${fmtTime(set)}');
          }
        }
      }
      final rf = wx?.fireAlertAt(s) ?? false;
      if (rf) {
        score -= 200;
        notes.add('Red Flag: no shooting');
      }
      if (s.isBefore(DateTime.now())) score -= 1000;
      out.add(SlotScore(i, s, free, total, score, h, daylight, rf, notes));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }
}

/// Calendar invite (.ics). Location is the meetup pin the organizer picked.
String buildIcs(Outing o, int slotIndex) {
  final start = o.slots[slotIndex].toUtc();
  final end = start.add(Duration(hours: o.durationH));
  String f(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}T'
      '${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}00Z';
  String esc(String s) => s.replaceAll('\\', '\\\\').replaceAll(',', '\\,').replaceAll(';', '\\;').replaceAll('\n', '\\n');
  final map = o.place == null ? '' : meetupMapLink(o.place!);
  final desc = StringBuffer()
    ..write('${activityLabel(o.activity)} outing')
    ..write(o.trailName != null ? ' · ${o.trailName}' : '')
    ..write(map.isNotEmpty ? '\nMeetup map: $map' : '')
    ..write('\nVerify posted signs and local orders before shooting.');
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Public Land//Outing//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:${o.id}-$slotIndex@public-land',
    'DTSTAMP:${f(DateTime.now().toUtc())}',
    'DTSTART:${f(start)}',
    'DTEND:${f(end)}',
    'SUMMARY:${esc(o.title)}',
    'LOCATION:${esc(o.placeName)}',
    if (o.place != null) 'GEO:${o.place!.lat.toStringAsFixed(5)};${o.place!.lon.toStringAsFixed(5)}',
    'DESCRIPTION:${esc(desc.toString())}',
    if (map.isNotEmpty) 'URL:$map',
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');
}

String meetupMapLink(LL p) =>
    'https://www.google.com/maps/search/?api=1&query=${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}';

String activityLabel(String a) => switch (a) { 'hike' => 'Hike', 'shoot' => 'Shoot', _ => 'Hike + Shoot' };
