# Public Land

Find, plan, and navigate to legal shooting spots and trails on US public land.
One Flutter codebase → an **Android app (APK)** and a **web app / PWA** that iPhone friends can use from Safari.

**$0 for everyone.** No accounts, no paid APIs, no map keys. Every data source is free and keyless.

- 📱 Android APK: **[Releases → latest](https://github.com/pdaddy-afk/public-land/releases/tag/latest)** (`public-land.apk`)
- 🌐 Web app / PWA: **https://pdaddy-afk.github.io/public-land/**

---

## Features (v1)

| | |
|---|---|
| **Explore** | Greeting, your town + current NWS weather, "Where to?" search (Photon/OSM), and a **Near you** list of the closest BLM / National Forest / state land with its shooting status. Red Flag banner when NWS has a fire-weather alert. |
| **Map: Clear to Shoot / Land / Trails** | MapLibre + OpenFreeMap dark basemap. **Clear to Shoot**: shootable public land as a soft sage wash, **150-yard (137 m) buffers** in muted rose around every OSM road, track, path, building and campsite in view, no-shoot land hatched red, closures hatched. **Land**: color by manager (BLM, USFS, State, NPS, FWS, DOD…). **Trails**: OSM paths + tracks; tap one for details. Bottom card: *You're clear to shoot / Not clear* for your GPS position (or the map center) with nearest trail and road distance. |
| **Spot card** | Tap anywhere: land manager, unit, status, the reasons, rules text, source/order link, nearest trail/road/building, distance + drive time (OSRM), **Navigate**, **Save**, **Plan outing**. |
| **Trail card** | Distance, elevation gain and an elevation chart (Open-Meteo), difficulty estimated from distance + gain, nearby clear areas, navigate to trailhead. |
| **Navigation** | Hand off to Google Maps, Apple Maps, or Android `geo:`. Or **follow me in-app**: live map with your recorded GPS track and a line to the pin. |
| **Offline (Android)** | Map button → download the area on screen (basemap tiles, plus land status, roads, trails and buffers cached on the device). |
| **On-site** | Your position, a **safe-direction cone** (widest open sector away from mapped roads, trails and buildings within ~½ mile), nearest trail + road, sunset time (computed locally), Red Flag check. |
| **Group outing planner** | Pick a spot and/or trail, Hike / Shoot / Both, and candidate times. **Share a link** — friends open it in any browser (iPhone Safari works, no app), pick the times they're free, Hike/Shoot/Both, their name, and gear they'll bring. **Best time** = most people free, then NWS forecast (temp, wind, rain), daylight, and Red Flag alerts. **Lock it in** → `.ics` calendar invite + meetup map link. |
| **Smart pack list** | Built from the activity, forecast temperature, wind / Red Flag, and remoteness. Sections: Always / Shooting / Hiking / Weather / Group gear. Checkboxes persist. Group gear can be assigned to friends and rides along in the outing link. |
| **Wrap up** | Trip distance (from the GPS track) and time, pack-out checklist (brass, targets, trash…), 5-star rating + note saved to the spot, share a recap. |
| **Saved & Trips** | Saved spots, outings and trips are stored **on your device only** (SharedPreferences / browser storage). |

### How shooting status works

| Land manager (PAD-US) | Default status |
|---|---|
| **BLM** | Allowed (safely; not on/across roads, not in developed sites) |
| **USFS** (National Forest) | Allowed, with 36 CFR 261.10(d) buffers: 150 yd from residences, buildings, campsites, developed recreation sites, occupied areas; not across/on roads or water |
| **NPS**, most **FWS** refuges, DOD, tribal, city/county/regional parks, NGO preserves | No shooting |
| State wildlife areas, state trust land, USBR/USACE | Check local rules |
| Not in PAD-US | Treated as private: no shooting |

**Restricted** = a known closure order. v1 ships a small curated dataset for Southern California
(San Diego, Riverside, San Bernardino, Orange, Los Angeles counties) in `assets/closures_socal.json`, each with its source link:

- Cleveland NF — target shooting not allowed on the Forest ([USFS](https://www.fs.usda.gov/r05/cleveland/fire/general-fire-restrictions))
- San Bernardino NF — designated, signed sites only, subject to daily fire level ([USFS](https://www.fs.usda.gov/r05/sanbernardino/recreation/opportunities/hunting-shooting))
- Angeles NF / San Gabriel Mtns NM — Forest Order 05-01-26-12: authorized ranges only, through Dec 31 2026
- BLM California Desert District seasonal fire order (Apr 15 – Oct 29 2026): no target shooting on BLM land in San Diego, W. Riverside, W. San Bernardino, E. LA, E. Kern counties ([BLM](https://www.blm.gov/announcement/blm-announces-seasonal-fire-restrictions-southern-california)); area boxes are approximate
- BLM site closures: High Point Rd (Aguanga), Table Mountain ACEC, Airport Mesa, McCain Valley, Otay Mountain Truck Trail corridor, Wonder Valley, Santa Rosa & San Jacinto Mtns NM, Dos Palmas, Big Morongo ([BLM CA list](https://www.blm.gov/programs/recreation/recreation-programs/recreational-shooting/california)). PLSS-section polygons come from the BLM CadNSDI service; others are approximate and labeled as such.
- BLM CA: no target shooting during any Red Flag Warning or Fire Weather Watch (checked live from NWS).

Everywhere else the app shows **"Check local orders"**: look up the local BLM field office or ranger district before you go.

---

## Install the Android app (sideload)

1. On your Android phone open **https://github.com/pdaddy-afk/public-land/releases/tag/latest** and tap **public-land.apk**.
2. When Android asks, allow your browser to **install unknown apps** (Settings → Apps → *your browser* → Install unknown apps → Allow). On older phones: Settings → Security → **Unknown sources**.
3. Open the download and tap **Install**. Allow location when the app asks.

The APK is signed with a debug key generated by CI (kept in the private GitHub Actions cache so updates install over the
old version). If that cache ever expires (unused for 7+ days) an update may refuse to install over the old app; uninstall first
(saved spots live on the phone and would be cleared). See *Stable signing* below for a permanent fix.

## iPhone friends: add the web app to the Home Screen

1. Open **https://pdaddy-afk.github.io/public-land/** (or the outing link you were sent) in **Safari**.
2. Tap the **Share** button → **Add to Home Screen** → **Add**.
3. Launch it from the new icon. It runs full-screen like an app. Free, no App Store, no account.

Outing links work straight in Safari without installing anything.

---

## Data sources & attribution

- **Public land**: USGS Gap Analysis Project, *Protected Areas Database of the United States (PAD-US) 4.1*, public domain — queried live from the USGS ArcGIS feature service `Fee_Managers_PADUS`.
- **Basemap**: [OpenFreeMap](https://openfreemap.org) vector tiles, © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors, OpenMapTiles.
- **Roads, trails, buildings, campsites**: © OpenStreetMap contributors, **ODbL**, via the public Overpass API (several mirrors tried in turn).
- **Search**: [Photon](https://photon.komoot.io) by komoot (OSM data). Debounced, 3+ characters, fair-use.
- **Weather & alerts**: [National Weather Service API](https://www.weather.gov/documentation/services-web-api) (api.weather.gov). The Android app sends a User-Agent; browsers can't set one.
- **Elevation**: [Open-Meteo Elevation API](https://open-meteo.com/en/docs/elevation-api) (Copernicus DEM GLO-90), CC BY 4.0.
- **Drive times**: [OSRM](https://project-osrm.org) public demo server (fair-use); falls back to an estimate.
- **PLSS sections for closures**: BLM CadNSDI PLSS service.
- Sunrise/sunset are computed on the device (NOAA algorithm).

## ⚠️ Legal disclaimer

Shooting status in this app is a **guide, not legal advice**. Land boundaries, closure orders, fire restrictions and county ordinances
change often and the data can be wrong or out of date. **Always verify posted signs and local orders**, follow federal, state and county
law, never shoot on or across roads, trails or water, use a safe backstop, and know your target and what is beyond it. You are responsible for your own safety and compliance.

## Privacy

- Saved spots, trips, tracks and outings stay **on the device**.
- Outing links carry only the outing details (title, place pin, times, activity, gear, organizer first name). **Never anyone's live location.**
- Reply links carry only the friend's name, picked times, activity and gear.
- No analytics, no accounts, no secrets in this repo.

---

## Optional: enable Supabase reply sync (free tier)

By default there's **no backend**: the outing is encoded in the share URL, and friends send back a *reply link* through any messenger
(the organizer opens it, or pastes it under **Trips → Link** / **Add reply link**). If you'd rather have replies sync automatically:

1. Create a free project at [supabase.com](https://supabase.com) (no card needed).
2. In **SQL Editor**, run [`docs/supabase.sql`](docs/supabase.sql).
3. In **Project Settings → API**, copy the **Project URL** and the **anon public** key.
4. In this GitHub repo: **Settings → Secrets and variables → Actions → New repository secret**:
   `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
5. Re-run the **Build APK + PWA** workflow (Actions tab → Run workflow). Both builds now use `SupabaseBackend`.

The anon key is designed to be public (it ships inside the web app); row-level security in the SQL limits what it can do.
Code: `lib/backend/backend_service.dart` (`BackendService` interface, `LinkBackend` default, `SupabaseBackend`).

## Build it yourself

```bash
flutter pub get
flutter run                     # Android device
flutter build web --base-href /public-land/
flutter build apk --release     # needs JDK 21
```

CI: `.github/workflows/build.yml` builds on every push to `main`, publishes the APK to the `latest` release and deploys the PWA to GitHub Pages (Settings → Pages → Source: **GitHub Actions**). A copy lives at `docs/ci/build.yml`.

### Stable signing (optional)

To keep the same signature across updates, generate a keystore on your own computer, store it as a base64 GitHub secret, and add a
`signingConfigs.release` block that reads it in CI. **Never commit a keystore or its passwords.**

## Known limits (v1)

- Closure data is curated only for Southern California; elsewhere you get "Check local orders".
- Buffers come from what's mapped in OpenStreetMap; unmapped homes, camps and dirt roads won't have buffers. Look around.
- PAD-US is a national compilation and can lag behind real boundaries; it doesn't show private inholdings perfectly.
- Offline tile download is Android-only (MapLibre limitation on web). The web app works online.
- GPS tracking runs while the app is open (no background tracking).
- The safe-direction cone only considers mapped features within ~½ mile — it does not know about terrain, backstops or people.
- Public free services (Overpass, Photon, OSRM demo) have fair-use limits and can be slow at busy times.

License: MIT.
