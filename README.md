# thessaloniki-bus-map

Interactive web map of Thessaloniki public transport in the visual logic of a
classic printed network map: **227 bus lines (OSETH) plus Metro Line 1** drawn
exactly along roadways and tunnels (own HMM/Viterbi map matching on an OSM graph),
line numbers written parallel to every street they use, labeled stops, true
roundabout arcs.

Sibling of [athens-bus-map](https://github.com/Miqell24/athens-bus-map) and
[krakow-bus-map](https://github.com/Miqell24/krakow-bus-map) — same pipeline and
same visual system, different city and feeds.

## Features

- GTFS (data.gov.gr, OSETH publishes ~2-week validity slices) matched onto the OSM
  road network — **weighted mean error 0.40 m** over 7 222 km of drawn route, only
  4 Viterbi breaks (79 m of raw trace) in the whole network.
- **The metro has no GTFS anywhere**: OSETH publishes buses only and the metro
  operator publishes nothing, so `pipeline/metro-feed.mjs` synthesizes a feed from
  the OSM route relation (station order) and deliberately omits `shapes.txt` — the
  HMM then reconstructs the geometry from the station sequence alone, routed
  through the OSM tunnels.
- KMK-style rendering: one stroke per roadway, aggregated line numbers rotated
  parallel to streets, half-disc stops turned to their side of the street, metro
  stations as full discs always labeled, termini with boxed line badges that fuse
  into one complex when they would collide at the current zoom.
- "Paper map" recolor of the base map: warm districts, green parks, real-blue
  water, pale-yellow motorways.
- Panel with mode visibility filters and a clickable line list (click a line to
  see its route with all stops).
- Poster-grade PNG export: the current view re-rendered in tiles at ~+3 zoom
  levels of extra detail (street and stop names become legible as you zoom into
  the image).
- GTFS shapes.txt quality report (`npm run report` → `data/gtfs-gaps-report.md`).

## Requirements

Node ≥ 18 (no npm dependencies), `curl`, `unzip`, internet on first run.

## Usage

```bash
npm run download   # OSETH GTFS + OSM (Overpass) + metro feed + MapLibre (cached)
npm run build      # extraction + map matching + GeoJSON files into data/out/
npm run serve      # http://localhost:8126
```

## Structure

- `pipeline/download.sh` — input data download
- `pipeline/metro-feed.mjs` — OSM route relations → synthetic metro GTFS (no shapes)
- `pipeline/build.mjs` — GTFS → OSM graph → HMM/Viterbi → `data/out/*.geojson`
- `pipeline/lib/` — csv (streaming), geo (local projection), graph (graph + Dijkstra), hmm (Viterbi)
- `pipeline/report-gaps.mjs` — GTFS shapes.txt gap report
- `web/` — MapLibre GL frontend (vendored, OpenFreeMap positron tiles)

Full plan and roadmap: [PLAN.md](PLAN.md).

## Data attribution

Map data © OpenStreetMap contributors · tiles by OpenFreeMap · bus timetables:
GTFS OSETH via data.gov.gr · metro alignment and stations: OpenStreetMap.
