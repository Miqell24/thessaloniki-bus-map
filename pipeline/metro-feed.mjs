// Synthesizes a minimal GTFS feed for the Thessaloniki Metro out of OSM route
// relations, because no metro feed exists: OSETH publishes buses only, and the
// metro operator publishes nothing at all.
//
// Only the parts build.mjs actually reads are written (routes/trips/stops/
// stop_times) and shapes.txt is deliberately LEFT OUT — that makes the pipeline
// take its no-shapes path, where the station sequence becomes the HMM
// observations and Viterbi routes the geometry along the OSM tunnels. So the
// relation supplies the stations and the OSM tunnel graph supplies the shape.
//
// Input:  data/osm/thessaloniki-metro.json (Overpass: rel[route=subway] + station nodes)
// Output: data/gtfs-t/{routes,trips,stops,stop_times}.txt
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'data/gtfs-t');

// Greek uppercase, the way the OSETH feed writes its stop names: accents dropped
// (tonos etc.), dialytika kept — "Νέα Ελβετία" → "ΝΕΑ ΕΛΒΕΤΙΑ".
const ACCENTS = /[̀́̄̆̓̔͂̓ͅ]/g; // tonos & co, NOT dialytika ̈
const upperGreek = (s) => s.normalize('NFD').replace(ACCENTS, '').normalize('NFC').toUpperCase();

const osm = JSON.parse(readFileSync(join(ROOT, 'data/osm/thessaloniki-metro.json'), 'utf8'));
const nodes = new Map();
for (const e of osm.elements) if (e.type === 'node') nodes.set(e.id, e);

// one route per ref ("1" → M1), one trip per relation (each is a direction)
const byRef = new Map();
for (const e of osm.elements) {
  if (e.type !== 'relation') continue;
  const ref = (e.tags?.ref || '').trim();
  if (!ref) continue;
  // relation member order IS the travel order; keep the stopping members only
  const stations = e.members
    .filter((m) => m.type === 'node' && nodes.has(m.ref))
    .filter((m) => {
      const t = nodes.get(m.ref).tags || {};
      return t.name && (/^(stop|station|halt)$/.test(t.railway || '') || t.public_transport === 'stop_position');
    });
  if (stations.length < 2) continue;
  let arr = byRef.get(ref);
  if (!arr) byRef.set(ref, (arr = []));
  arr.push({ rel: e, stations });
}

const rows = { routes: [], trips: [], stops: [], stop_times: [] };
const seenStops = new Set();

for (const [ref, rels] of [...byRef].sort()) {
  const line = 'M' + ref;
  const long = rels[0].rel.tags?.['name:en'] || rels[0].rel.tags?.name || `Line ${ref}`;
  const color = (rels[0].rel.tags?.colour || '#e30613').replace('#', '');
  rows.routes.push([line, 'THEMA', line, long, '1', color, 'FFFFFF']);

  rels.slice(0, 2).forEach(({ rel, stations }, dir) => {
    const tripId = `${line}_${dir}`;
    rows.trips.push([line, 'ALL', tripId, rel.tags?.to || '', String(dir), '']);
    stations.forEach((m, i) => {
      const n = nodes.get(m.ref);
      const stopId = 'osm' + n.id;
      if (!seenStops.has(stopId)) {
        seenStops.add(stopId);
        rows.stops.push([stopId, upperGreek(n.tags?.name || ''), n.lat, n.lon, '0', '']);
      }
      // ~2 min between stations — times are never read for geometry, but a valid
      // feed keeps report-gaps.mjs and any external GTFS tool happy
      const t = `05:${String(i * 2).padStart(2, '0')}:00`;
      rows.stop_times.push([tripId, t, t, stopId, String(i + 1)]);
    });
    console.log(`${line} dir ${dir}: ${stations.length} stations (${rel.tags?.from || '?'} → ${rel.tags?.to || '?'})`);
  });
}

const q = (v) => (/[",]/.test(String(v)) ? '"' + String(v).replace(/"/g, '""') + '"' : String(v));
const csv = (header, data) => header + '\n' + data.map((r) => r.map(q).join(',')).join('\n') + '\n';
mkdirSync(OUT, { recursive: true });
writeFileSync(join(OUT, 'routes.txt'), csv('route_id,agency_id,route_short_name,route_long_name,route_type,route_color,route_text_color', rows.routes));
writeFileSync(join(OUT, 'trips.txt'), csv('route_id,service_id,trip_id,trip_headsign,direction_id,shape_id', rows.trips));
writeFileSync(join(OUT, 'stops.txt'), csv('stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station', rows.stops));
writeFileSync(join(OUT, 'stop_times.txt'), csv('trip_id,arrival_time,departure_time,stop_id,stop_sequence', rows.stop_times));
console.log(`metro feed: ${rows.routes.length} route(s), ${rows.trips.length} trips, ${rows.stops.length} stations → data/gtfs-t/`);
