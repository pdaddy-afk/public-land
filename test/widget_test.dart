import 'package:flutter_test/flutter_test.dart';
import 'package:public_land/services/geo.dart';
import 'package:public_land/services/models.dart';
import 'package:public_land/services/pack_list.dart';

void main() {
  test('distance and bearing', () {
    const a = LL(33.0, -117.0), b = LL(33.0, -116.99);
    expect(Geo.distance(a, b), closeTo(933, 5));
    expect(Geo.bearing(a, b), closeTo(90, 0.1));
  });

  test('outing link round trip', () {
    final o = Outing(id: 'abc', title: 'Sat', placeName: 'Pit', slots: [DateTime(2030, 1, 5, 7, 30)], organizer: 'B');
    final back = Outing.fromShare(LinkCodec.decode(LinkCodec.encode(o.toShare())));
    expect(back.title, 'Sat');
    expect(back.slots.first, DateTime(2030, 1, 5, 7, 30));
  });

  test('pack list has sections', () {
    final items = buildPackList(const PackInput(activity: 'both', tempF: 95, windMph: 22, redFlag: true));
    expect(items.any((i) => i.section == 'Shooting'), true);
    expect(items.any((i) => i.id == 'extinguisher'), true);
  });

  test('sunset exists', () {
    expect(Sun.sunset(DateTime(2026, 10, 20), const LL(33.1, -117.1)), isNotNull);
  });
}
