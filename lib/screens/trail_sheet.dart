import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/clearance.dart';
import '../services/geo.dart';
import '../services/osm_service.dart';
import '../services/weather_service.dart';
import '../widgets/glass.dart';
import 'spot_sheet.dart';

/// Trail detail card: distance, gain, difficulty, elevation chart, nearby clear areas.
class TrailSheet extends StatefulWidget {
  final Trail trail;
  const TrailSheet({super.key, required this.trail});
  @override
  State<TrailSheet> createState() => _TrailSheetState();
}

class _TrailSheetState extends State<TrailSheet> {
  List<double>? _elev;
  String? _err;
  List<(LL, double)> _clear = [];

  @override
  void initState() {
    super.initState();
    _load();
    _findClear();
  }

  Future<void> _load() async {
    try {
      final e = await ElevationService.profile(widget.trail.line);
      if (mounted) setState(() => _elev = e);
    } catch (e) {
      if (mounted) setState(() => _err = 'Elevation unavailable right now');
    }
  }

  /// Scan a ring around the trail for points that pass every local check.
  void _findClear() {
    final h = OsmService.instance.last;
    final out = <(LL, double)>[];
    final line = widget.trail.line;
    final anchors = [line.first, line[line.length ~/ 2], line.last];
    for (final a in anchors) {
      for (var b = 0; b < 360; b += 30) {
        for (final d in [250.0, 450.0, 700.0]) {
          final p = Geo.destination(a, b.toDouble(), d);
          final c = ClearanceService.evaluateLocal(p, h);
          if (c.clear) {
            out.add((p, Geo.distance(widget.trail.trailhead, p)));
            break;
          }
        }
      }
    }
    out.sort((x, y) => x.$2.compareTo(y.$2));
    final dedup = <(LL, double)>[];
    for (final o in out) {
      if (dedup.every((d) => Geo.distance(d.$1, o.$1) > 300)) dedup.add(o);
      if (dedup.length >= 3) break;
    }
    _clear = dedup;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trail;
    final gainM = _elev == null ? null : ElevationService.gainMeters(_elev!);
    final diff = gainM == null ? null : ElevationService.difficulty(t.lengthM, gainM);
    final diffColor = switch (diff) { 'Easy' => C.sage, 'Moderate' => C.amber, 'Hard' => C.red, _ => C.text2 };
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(t.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        Text('OpenStreetMap ${t.kind}', style: const TextStyle(fontSize: 15, color: C.text3)),
        const SizedBox(height: 14),
        Row(children: [
          _stat('Distance', Geo.fmtMiles(t.lengthM)),
          _stat('Gain', gainM == null ? '…' : '${(gainM * 3.28084).round()} ft'),
          _stat('Difficulty', diff ?? '…', color: diffColor),
        ]),
        const SizedBox(height: 14),
        Glass(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
          child: SizedBox(
            height: 150,
            child: _elev == null
                ? Center(
                    child: _err != null
                        ? Text(_err!, style: const TextStyle(color: C.text2))
                        : const CircularProgressIndicator(color: C.sage))
                : CustomPaint(painter: ElevationPainter(_elev!, t.lengthM), size: Size.infinite),
          ),
        ),
        const SizedBox(height: 6),
        const Text('Elevation: Open-Meteo (Copernicus DEM). Difficulty estimated from distance + gain.',
            style: TextStyle(fontSize: 13, color: C.text3)),
        const SectionTitle('Nearby clear areas'),
        if (_clear.isEmpty)
          const Text('No clear ground found near this trail in the loaded area. Try zooming out on the map or pick a spot manually.',
              style: TextStyle(fontSize: 16, color: C.text2)),
        for (final (p, d) in _clear)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Glass(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: () => showGlassSheet(context, (_) => SpotSheet(point: p, name: 'Clear spot near ${t.name}')),
              child: Row(children: [
                const StatusDot(C.sage),
                const SizedBox(width: 12),
                Expanded(child: Text('Clear ground · ${Geo.fmtDist(d)} from trailhead', style: const TextStyle(fontSize: 17))),
                const Icon(Icons.chevron_right_rounded, color: C.text2),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        PrimaryButton('Navigate to trailhead', icon: Icons.navigation_rounded, onPressed: () {
          showGlassSheet(context, (_) => NavChooser(dest: t.trailhead, label: '${t.name} trailhead'));
        }),
      ]),
    );
  }

  Widget _stat(String k, String v, {Color? color}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 15, color: C.text3)),
          Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color ?? C.text)),
        ]),
      );
}

class ElevationPainter extends CustomPainter {
  final List<double> elev;
  final double lengthM;
  ElevationPainter(this.elev, this.lengthM);

  @override
  void paint(Canvas canvas, Size size) {
    if (elev.length < 2) return;
    final lo = elev.reduce(math.min), hi = elev.reduce(math.max);
    final span = math.max(hi - lo, 10.0);
    const left = 44.0, bottom = 20.0;
    final w = size.width - left, h = size.height - bottom;
    Offset pt(int i) => Offset(left + w * i / (elev.length - 1), h - (elev[i] - lo) / span * (h - 8));
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < elev.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(left + w, h)
      ..lineTo(left, h)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [
            C.trail.withValues(alpha: 0.45),
            C.trail.withValues(alpha: 0.02),
          ]).createShader(Rect.fromLTWH(left, 0, w, h)));
    canvas.drawPath(
        path,
        Paint()
          ..color = C.trail
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke);
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void label(String s, Offset o) {
      tp.text = TextSpan(text: s, style: const TextStyle(fontSize: 12, color: C.text2));
      tp.layout();
      tp.paint(canvas, o);
    }

    label('${(hi * 3.28084).round()} ft', const Offset(0, 0));
    label('${(lo * 3.28084).round()} ft', Offset(0, h - 14));
    label('0', Offset(left, h + 4));
    label(Geo.fmtMiles(lengthM), Offset(left + w - 40, h + 4));
  }

  @override
  bool shouldRepaint(covariant ElevationPainter old) => old.elev != elev;
}
