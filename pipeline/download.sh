#!/usr/bin/env bash
# Downloads input data: OSETH GTFS feed (data.gov.gr), OSM network (Overpass), MapLibre GL.
# Everything is cached — re-running only fetches what is missing.
#
# Thessaloniki quirk: there is NO metro GTFS anywhere — the transport authority
# OSETH publishes buses only and the metro operator publishes no feed at all — so
# the metro feed is synthesized from OSM route relations (pipeline/metro-feed.mjs).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/gtfs data/gtfs-t data/osm web/vendor

# A downloaded extract is only accepted if it PARSES and carries a plausible
# number of elements. `grep -q '"elements"'` — the guard this family used
# everywhere — passes on a truncated response too: Brașov's roads arrived as a
# 65 kB fragment that still contained the string, was taken for complete, and
# silently skipped the city (16.08.2026).
# The minimum differs by extract, so the caller passes its own floor: the roads
# run to 49 k ways, but the metro is one line — 62 tunnel ways and 44 relation
# members — so anything above 20 would reject a perfectly good download.
# A rejected file is deleted rather than left behind — the `[ ! -f … ]` gates
# below only ask whether the file exists, so a fragment on disk would be taken
# for a finished download on the next run.
ok_json () { # $1=file  $2=minimum element count
  python3 - "$1" "$2" <<'PYEOF' 2>/dev/null
import json, sys
try:
    sys.exit(0 if len(json.load(open(sys.argv[1])).get("elements", [])) >= int(sys.argv[2]) else 1)
except Exception:
    sys.exit(1)
PYEOF
}

# 1) GTFS — OSETH buses, published on data.gov.gr in ~2-week validity slices.
#    This is the slice valid 14/07/2026-03/08/2026 (published 17.07.2026); newer
#    slices show up as new resources of dataset 42c9a7da-c86c-48b1-914c-f340e8bef00d.
if [ ! -f data/gtfs/routes.txt ]; then
  echo "== oseth gtfs =="
  curl -fL --retry 3 --max-time 600 -o data/oseth_gtfs.zip "https://data.gov.gr/dataset/42c9a7da-c86c-48b1-914c-f340e8bef00d/resource/8edcc617-7d0e-4832-9804-96c9811fabfd/download/20260717_gtfs.zip"
  unzip -o data/oseth_gtfs.zip -d data/gtfs
fi

# 2) OSM — roadways over the whole OSETH network (GTFS shapes extent + margin:
#    Lagkadas - Chalkidona - Vasilika - Nea Michaniona), incl. highway=construction
if [ ! -f data/osm/thessaloniki.json ]; then
  echo "== Overpass (roads) =="
  Q='[out:json][timeout:900];way(40.34,22.52,41.00,23.27)["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|busway|construction|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$"];out geom;'
  ok=0
  for EP in "https://overpass-api.de/api/interpreter" \
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
            "https://overpass.kumi.systems/api/interpreter"; do
    echo "-- $EP"
    if curl -fsS --max-time 900 -o data/osm/thessaloniki.json --data-urlencode "data=$Q" "$EP" \
       && ok_json "data/osm/thessaloniki.json" 2000; then
      ok=1; break
    fi
  done
  [ "$ok" = 1 ] || { rm -f data/osm/thessaloniki.json; echo "Overpass: all mirrors failed" >&2; exit 1; }
fi

# 2b) OSM — every NAMED feature in the same bbox, tags only. Not geometry: this
#     is the accent dictionary. The GTFS shouts its stop names in capitals, and
#     Greek writes accents only in lowercase, so the feed cannot tell us that
#     ΑΤΤΙΚΗΣ is Αττικής — but OSM spells the same words properly on streets,
#     squares, districts and churches. See pipeline/lib/greek.mjs.
if [ ! -f data/osm/thessaloniki-names.json ]; then
  echo "== Overpass (names for the Greek dictionary) =="
  QN='[out:json][timeout:600];nwr(40.34,22.52,41.00,23.27)[name][~"^(amenity|place|tourism|leisure|shop|building|railway|public_transport|natural|waterway|landuse|historic|office|man_made)$"~"."];out tags;'
  ok=0
  for EP in "https://overpass-api.de/api/interpreter" \
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
            "https://overpass.kumi.systems/api/interpreter"; do
    echo "-- $EP"
    if curl -fsS --max-time 600 -o data/osm/thessaloniki-names.json --data-urlencode "data=$QN" "$EP" \
       && ok_json "data/osm/thessaloniki-names.json" 2000; then
      ok=1; break
    fi
  done
  # not fatal: without it the stop names simply come out unaccented
  [ "$ok" = 1 ] || { rm -f data/osm/thessaloniki-names.json; echo "Overpass (names): all mirrors failed — stop names will lose their accents" >&2; }
fi

# 2c) OSM — metro tunnels (separate graph). Only railway=subway: Line 1 runs
#     entirely underground, and keeping mainline rail out of the graph stops the
#     matcher from straying onto the OSE tracks beside New Railway Station.
if [ ! -f data/osm/thessaloniki-rail.json ]; then
  echo "== Overpass (metro tunnels) =="
  QT='[out:json][timeout:300];way(40.50,22.80,40.72,23.10)["railway"="subway"];out geom;'
  ok=0
  for EP in "https://overpass-api.de/api/interpreter" \
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
            "https://overpass.kumi.systems/api/interpreter"; do
    echo "-- $EP"
    if curl -fsS --max-time 300 -o data/osm/thessaloniki-rail.json --data-urlencode "data=$QT" "$EP" \
       && ok_json "data/osm/thessaloniki-rail.json" 20; then
      ok=1; break
    fi
  done
  [ "$ok" = 1 ] || { rm -f data/osm/thessaloniki-rail.json; echo "Overpass (rail): all mirrors failed" >&2; exit 1; }
fi

# 2d) OSM — metro line relations plus their station members (metro-feed.mjs input).
#     The relations list railway=stop / public_transport=stop_position nodes, which
#     is what we want: unlike station nodes (placed over the entrances) these sit
#     exactly on the tunnel axis, so they snap onto the graph with no slack.
if [ ! -f data/osm/thessaloniki-metro.json ]; then
  echo "== Overpass (metro relations) =="
  QR='[out:json][timeout:300];rel(40.50,22.80,40.72,23.10)["type"="route"]["route"="subway"]->.r;.r out body;node(r.r);out;'
  ok=0
  for EP in "https://overpass-api.de/api/interpreter" \
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
            "https://overpass.kumi.systems/api/interpreter"; do
    echo "-- $EP"
    if curl -fsS --max-time 300 -o data/osm/thessaloniki-metro.json --data-urlencode "data=$QR" "$EP" \
       && ok_json "data/osm/thessaloniki-metro.json" 20; then
      ok=1; break
    fi
  done
  [ "$ok" = 1 ] || { rm -f data/osm/thessaloniki-metro.json; echo "Overpass (metro relations): all mirrors failed" >&2; exit 1; }
fi

# 3) synthesize the metro GTFS feed out of those relations
if [ ! -f data/gtfs-t/routes.txt ]; then
  echo "== metro feed (synthesized) =="
  node pipeline/metro-feed.mjs
fi

# 4) MapLibre GL (vendored, no CDN at runtime)
if [ ! -f web/vendor/maplibre-gl.js ]; then
  echo "== MapLibre GL =="
  curl -fL --retry 3 -o web/vendor/maplibre-gl.js  https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.js
  curl -fL --retry 3 -o web/vendor/maplibre-gl.css https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.css
fi

echo "OK — data ready:"
du -sh data/oseth_gtfs.zip data/osm/thessaloniki.json data/osm/thessaloniki-rail.json web/vendor/maplibre-gl.js 2>/dev/null || true
