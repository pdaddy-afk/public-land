import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Everything is stored on this device only (SharedPreferences / browser localStorage).
class Store extends ChangeNotifier {
  Store._();
  static final Store instance = Store._();
  late SharedPreferences _p;

  List<SavedSpot> spots = [];
  List<Trip> trips = [];
  List<Outing> outings = [];
  String userName = '';
  String units = 'imperial';

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    spots = _list('spots').map(SavedSpot.fromJson).toList();
    trips = _list('trips').map(Trip.fromJson).toList();
    outings = _list('outings').map(Outing.fromJson).toList();
    userName = _p.getString('userName') ?? '';
  }

  List<Map<String, dynamic>> _list(String k) {
    final raw = _p.getString(k);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save() async {
    await _p.setString('spots', jsonEncode([for (final s in spots) s.toJson()]));
    await _p.setString('trips', jsonEncode([for (final t in trips) t.toJson()]));
    await _p.setString('outings', jsonEncode([for (final o in outings) o.toJson()]));
    notifyListeners();
  }

  Future<void> setUserName(String n) async {
    userName = n.trim();
    await _p.setString('userName', userName);
    notifyListeners();
  }

  Future<void> upsertSpot(SavedSpot s) async {
    spots.removeWhere((x) => x.id == s.id);
    spots.insert(0, s);
    await _save();
  }

  Future<void> removeSpot(String id) async {
    spots.removeWhere((x) => x.id == id);
    await _save();
  }

  SavedSpot? spotNear(double lat, double lon) {
    for (final s in spots) {
      if ((s.p.lat - lat).abs() < 0.0005 && (s.p.lon - lon).abs() < 0.0005) return s;
    }
    return null;
  }

  Future<void> upsertTrip(Trip t) async {
    trips.removeWhere((x) => x.id == t.id);
    trips.insert(0, t);
    await _save();
  }

  Future<void> removeTrip(String id) async {
    trips.removeWhere((x) => x.id == id);
    await _save();
  }

  Future<void> upsertOuting(Outing o) async {
    final i = outings.indexWhere((x) => x.id == o.id);
    if (i >= 0) {
      outings[i] = o;
    } else {
      outings.insert(0, o);
    }
    await _save();
  }

  Future<void> removeOuting(String id) async {
    outings.removeWhere((x) => x.id == id);
    await _save();
  }

  Outing? outing(String id) {
    for (final o in outings) {
      if (o.id == id) return o;
    }
    return null;
  }

  // Pack list check state, keyed by list id.
  Set<String> packChecks(String listId) => (_p.getStringList('pack:$listId') ?? []).toSet();
  Future<void> setPackChecks(String listId, Set<String> v) async {
    await _p.setStringList('pack:$listId', v.toList());
  }

  // Offline data cache (Android): land + OSM data for downloaded areas.
  Future<void> putCache(String key, String value) async {
    try {
      await _p.setString('cache:$key', value);
    } catch (_) {}
  }

  String? getCache(String key) => _p.getString('cache:$key');

  List<String> get offlineAreas => _p.getStringList('offlineAreas') ?? [];
  Future<void> setOfflineAreas(List<String> v) => _p.setStringList('offlineAreas', v);
}
