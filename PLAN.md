# PLAN — Interactive Thessaloniki transport map

Target: an interactive (zoom/pan) web map of Thessaloniki public transport in the
visual logic of a printed network map: lines drawn **exactly along roadways and
tunnels**, line numbers written along every street they use, stops labeled, correct
roundabout arcs and intersection turns. Third city of the krakow-bus-map /
athens-bus-map pipeline.

## Architecture

- **Plain JavaScript**: pipeline in Node ≥ 18 (no npm dependencies), frontend in the browser.
- **Input data**: OSETH bus GTFS from data.gov.gr (dataset
  `42c9a7da-c86c-48b1-914c-f340e8bef00d`, ~2-week validity slices), a metro feed
  synthesized from OSM route relations, and the OSM road/tunnel network via the
  Overpass API (bbox of the whole Thessaloniki regional unit served by OSETH).
- **Map matching**: own HMM/Viterbi implementation (Newson–Krumm 2009) on a directed
  graph — the heart of the project.
- **Frontend**: MapLibre GL JS (vendored) + OSM vector tiles from OpenFreeMap
  (`positron` style, recolored to a paper-map palette). Static server on port **8126**.

## Thessaloniki-specific data quirks (vs Athens / Kraków)

1. **The metro has no GTFS at all.** OSETH's feed is buses only (`route_type` 3
   throughout) and the metro operator publishes nothing, so `pipeline/metro-feed.mjs`
   builds one from the OSM relation `route=subway`: member order = travel order,
   `railway=stop` members = stations (they sit on the tunnel axis, unlike
   entrance-based station nodes), Greek names uppercased accent-free to match the
   feed's own style. `shapes.txt` is intentionally omitted so the pipeline takes its
   no-shapes path and routes the geometry through the OSM tunnels.
2. **Dense, well-aligned shapes**: median point spacing ~14 m (p95 ~86 m), so
   `GAP_MIN` is back to 120 m as in Kraków (Athens needed 250 m). Result: 0.40 m
   weighted mean error, 4 breaks in the whole network.
3. **No trolleybuses** (the last ones ran in 2011) — the trolleybus green and the
   dashed shared-corridor overlay of the sibling maps simply never trigger here.
4. **Line 2 (Kalamaria extension)** is still `railway=construction` in OSM and opens
   in August 2026; its color (`#0070ff`) is already in the config, so once OSM flips
   the tag it enters the map with a re-run of `npm run download && npm run build`
   (delete `data/osm/thessaloniki-*.json` and `data/gtfs-t/` first to refetch).
5. **Metro station names get their own top-priority symbol layer**: 13 stations under
   busy avenues lost the collision fight against bus stops and street numbers, so
   `stops-metro-names` is moved above everything (symbol placement runs top-first).
6. **Initial view is explicit, not `fitBounds`**: the OSETH network reaches Lagkadas
   and Nea Michaniona ~35 km out, so fitting the data bbox would open on countryside.

## Pipeline stages

1. `pipeline/download.sh` — GTFS zip, Overpass roads (bbox 40.34–41.00, 22.52–23.27),
   Overpass metro tunnels + relations (40.50–40.72, 22.80–23.10), metro feed, MapLibre.
2. `build.mjs` — routes → representative shape per line+direction (most trips);
   stop sequences from streamed `stop_times.txt`.
3. Directed graph from OSM (`lib/graph.mjs`): oneway/roundabout rules, bus-gate
   access, penalty-weighted contraflow; rail mode for the metro.
4. HMM/Viterbi (`lib/hmm.mjs`): emission σ, transition |route − straight|/β via
   capped Dijkstra; controlled breaks bridged by routing; raw-trace fallback when
   OSM lacks the road.
5. Data products (`data/out/`): `streets.geojson` (merged strokes per roadway),
   `labels.geojson` (one rotated number label per street × line set),
   `stops.geojson` (snapped, termini flagged), `badges.geojson` (terminus line boxes
   per zoom band), `route.geojson`, `meta.json`.
6. Frontend (`web/`): KMK-style strokes (bus navy, metro red translucent ribbon),
   rotated number labels beside streets, half-disc stops, boxed terminus badges,
   mode filters + clickable line list, poster PNG export (tiled hidden-map render).

## Current state

- 227 bus lines + M1 — full network matched, 353 directions, 7 222 km drawn.
- Weighted mean error **0.40 m**; 4 Viterbi breaks (79 m raw) in lines 38, 45Y, 83N;
  no observation left without candidates. Metro: zero breaks, 8.07 km
  station-to-station, all 13 stations merged to one disc each.
- 3 653 stop poles, 2 244 name labels, 1 710 number labels, 1 718 badge boxes across
  4 zoom bands (56 colliding grids fused). Build ~52 s.
- Verified in browser: rendering, filters, line selection, badge fusion per zoom
  band, every metro station labeled, PNG export (5826×6561, 21 MB), no console errors.

## Roadmap

1. Metro Line 2 (Kalamaria extension) when it opens — see quirk 4 above.
2. KMK-style corridors: merging twin carriageways into one stroke — deferred
   ("corridor axes" preprocessing).
3. Route variants + one-way arrows; line/stop search; GTFS-RT (live positions).
4. Hosting on GitHub Pages from `main:/docs`, like the two sibling maps.
