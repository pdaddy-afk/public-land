import 'dart:async';

import 'package:flutter/material.dart';

import '../services/geo.dart';
import '../services/places_service.dart';
import '../services/store.dart';
import '../widgets/glass.dart';

class SearchPick {
  final String name;
  final LL p;
  SearchPick(this.name, this.p);
}

/// "Where to?" search: saved spots first, then the free Photon geocoder.
class SearchSheet extends StatefulWidget {
  final LL? bias;
  const SearchSheet({super.key, this.bias});
  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  final _ctl = TextEditingController();
  Timer? _deb;
  List<Place> _results = [];
  bool _busy = false;
  String? _err;

  void _changed(String q) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    if (q.trim().length < 3) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await PlacesService.search(q, bias: widget.bias);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _err = 'Search is unavailable right now.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _deb?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _ctl.text.trim().toLowerCase();
    final saved = Store.instance.spots.where((s) => q.isEmpty || s.name.toLowerCase().contains(q)).take(5).toList();
    // Accept raw "lat, lon" too.
    final m = RegExp(r'^\s*(-?\d+(\.\d+)?)\s*[, ]\s*(-?\d+(\.\d+)?)\s*$').firstMatch(_ctl.text);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _ctl,
        autofocus: true,
        onChanged: (v) {
          setState(() {});
          _changed(v);
        },
        onSubmitted: _run,
        style: const TextStyle(fontSize: 19),
        decoration: const InputDecoration(
          hintText: 'Where to? (place, trail, or lat, lon)',
          prefixIcon: Icon(Icons.search_rounded, color: C.text2),
        ),
      ),
      const SizedBox(height: 12),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          if (m != null)
            _tile(Icons.place_outlined, 'Go to ${m.group(1)}, ${m.group(3)}', 'Coordinates',
                () => Navigator.pop(context, SearchPick('Dropped pin', LL(double.parse(m.group(1)!), double.parse(m.group(3)!))))),
          if (saved.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(4, 8, 4, 4), child: Text('Saved', style: TextStyle(color: C.text3))),
          for (final s in saved)
            _tile(Icons.bookmark_rounded, s.name, s.manager.isEmpty ? 'Saved spot' : s.manager,
                () => Navigator.pop(context, SearchPick(s.name, s.p))),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: C.sage))),
          if (_err != null) Padding(padding: const EdgeInsets.all(12), child: Text(_err!, style: const TextStyle(color: C.amber))),
          for (final r in _results)
            _tile(Icons.travel_explore_rounded, r.name, r.detail, () => Navigator.pop(context, SearchPick(r.name, r.p))),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Search by Photon · © OpenStreetMap contributors', style: TextStyle(fontSize: 13, color: C.text3)),
          ),
        ]),
      ),
    ]);
  }

  Widget _tile(IconData i, String t, String s, VoidCallback onTap) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        leading: Icon(i, color: C.text2),
        title: Text(t, style: const TextStyle(fontSize: 18)),
        subtitle: s.isEmpty ? null : Text(s, style: const TextStyle(fontSize: 15, color: C.text2)),
        onTap: onTap,
      );
}
