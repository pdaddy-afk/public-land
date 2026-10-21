class PackItem {
  final String id;
  final String label;
  final String section; // Always | Shooting | Hiking | Weather | Group gear
  final String? why;
  const PackItem(this.id, this.label, this.section, [this.why]);
}

class PackInput {
  final String activity; // hike | shoot | both
  final int? tempF;
  final double? windMph;
  final bool redFlag;
  final bool remote;
  final int precipPct;
  final int groupSize;
  const PackInput({
    required this.activity,
    this.tempF,
    this.windMph,
    this.redFlag = false,
    this.remote = false,
    this.precipPct = 0,
    this.groupSize = 1,
  });
}

const packSections = ['Always', 'Shooting', 'Hiking', 'Weather', 'Group gear'];

/// Rules-based pack list. Simple, offline, explainable.
List<PackItem> buildPackList(PackInput i) {
  final shoot = i.activity != 'hike';
  final hike = i.activity != 'shoot';
  final items = <PackItem>[
    const PackItem('water', 'Water (1 L per person per 2 hrs, more if hot)', 'Always'),
    const PackItem('firstaid', 'First-aid kit', 'Always'),
    const PackItem('phone', 'Charged phone + battery pack', 'Always'),
    const PackItem('map', 'Offline map saved', 'Always', 'Cell coverage is spotty on public land'),
    const PackItem('id', 'ID and any permits / hunting license', 'Always'),
    const PackItem('trash', 'Trash bags (pack it out)', 'Always'),
    const PackItem('snacks', 'Snacks / lunch', 'Always'),
  ];
  if (i.remote) {
    items.addAll(const [
      PackItem('tellsomeone', 'Tell someone your plan and return time', 'Always', 'Remote area'),
      PackItem('spare', 'Spare tire, jack, tire plug kit', 'Always', 'Remote dirt roads'),
      PackItem('extrawater', 'Extra 1 gal water in the truck', 'Always', 'Remote area'),
    ]);
  }
  if (shoot) {
    items.addAll([
      const PackItem('eyes', 'Eye protection', 'Shooting'),
      const PackItem('ears', 'Ear protection', 'Shooting'),
      const PackItem('targets', 'Paper or cardboard targets + stand', 'Shooting', 'No glass, no exploding targets'),
      const PackItem('backstop', 'Check for a safe dirt backstop', 'Shooting'),
      const PackItem('ammo', 'Ammo (no steel-core, tracer or incendiary)', 'Shooting'),
      const PackItem('brass', 'Brass bag / bucket', 'Shooting'),
      const PackItem('stapler', 'Staple gun + staples', 'Shooting'),
      const PackItem('cleaning', 'Cleaning kit', 'Shooting'),
      if (i.redFlag || (i.windMph ?? 0) >= 20)
        const PackItem('extinguisher', 'Fire extinguisher + shovel', 'Shooting', 'Fire risk: wind or Red Flag'),
    ]);
  }
  if (hike) {
    items.addAll([
      const PackItem('shoes', 'Hiking shoes or boots', 'Hiking'),
      const PackItem('pack', 'Daypack', 'Hiking'),
      const PackItem('sun', 'Sunscreen, hat, sunglasses', 'Hiking'),
      const PackItem('headlamp', 'Headlamp', 'Hiking', 'In case you finish after sunset'),
      const PackItem('poles', 'Trekking poles', 'Hiking'),
    ]);
  }
  final t = i.tempF;
  if (t != null && t >= 85) {
    items.addAll([
      PackItem('heat', 'Extra water + electrolytes ($t°F forecast)', 'Weather', 'Hot'),
      const PackItem('shade', 'Shade canopy or umbrella', 'Weather', 'Hot'),
      const PackItem('cooler', 'Cooler with ice', 'Weather', 'Hot'),
    ]);
  }
  if (t != null && t <= 50) {
    items.addAll([
      PackItem('layers', 'Warm layers + beanie ($t°F forecast)', 'Weather', 'Cold'),
      const PackItem('gloves', 'Gloves', 'Weather', 'Cold'),
    ]);
  }
  if ((i.windMph ?? 0) >= 15) {
    items.add(PackItem('wind', 'Windbreaker; weigh down targets (${i.windMph!.round()} mph)', 'Weather', 'Windy'));
  }
  if (i.precipPct >= 30) {
    items.add(PackItem('rain', 'Rain shell (${i.precipPct}% chance)', 'Weather', 'Rain'));
  }
  if (i.redFlag) {
    items.add(const PackItem('redflag', 'Red Flag Warning: plan to hike only, no shooting', 'Weather', 'NWS alert'));
  }
  {
    items.addAll([
      if (shoot) const PackItem('g_table', 'Folding table', 'Group gear'),
      if (shoot) const PackItem('g_targets', 'Target frames', 'Group gear'),
      const PackItem('g_chairs', 'Camp chairs', 'Group gear'),
      const PackItem('g_cooler', 'Cooler + drinks', 'Group gear'),
      const PackItem('g_firstaid', 'Trauma / bleed kit', 'Group gear'),
      const PackItem('g_shade', 'Pop-up shade', 'Group gear'),
      if (i.remote) const PackItem('g_comms', 'Satellite messenger or radios', 'Group gear'),
    ]);
  }
  return items;
}
