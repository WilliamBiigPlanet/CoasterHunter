// Wikidata — CC0, so anything taken from here carries no downstream obligation
// and can be merged freely into our own database. Attribute coverage is thin
// (roughly 1 in 7 coasters has a height), so this is a breadth and
// cross-reference layer rather than a spec source.

import { getJSON } from "../util/http.mjs";
import { round } from "../util/units.mjs";

const ENDPOINT = "https://query.wikidata.org/sparql";

export const SOURCE = {
  key: "wikidata",
  name: "Wikidata",
  url: "https://www.wikidata.org",
  licence: "CC0 1.0 (public domain)",
};

const COASTER_QUERY = `
SELECT ?item ?itemLabel ?height ?speed ?length ?inception ?parkLabel
       ?makerLabel ?coord ?rcdb WHERE {
  ?item wdt:P31/wdt:P279* wd:Q204832 .
  OPTIONAL { ?item wdt:P2048 ?height }
  OPTIONAL { ?item wdt:P2052 ?speed }
  OPTIONAL { ?item wdt:P2043 ?length }
  OPTIONAL { ?item wdt:P571  ?inception }
  OPTIONAL { ?item wdt:P276  ?park }
  OPTIONAL { ?item wdt:P176  ?maker }
  OPTIONAL { ?item wdt:P625  ?coord }
  OPTIONAL { ?item wdt:P4803 ?rcdb }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en" }
}`;

const PARK_QUERY = `
SELECT ?item ?itemLabel ?coord ?countryLabel ?inception WHERE {
  ?item wdt:P31/wdt:P279* wd:Q194195 .
  OPTIONAL { ?item wdt:P625 ?coord }
  OPTIONAL { ?item wdt:P17  ?country }
  OPTIONAL { ?item wdt:P571 ?inception }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en" }
}`;

async function sparql(query, label) {
  const res = await getJSON(ENDPOINT, {
    body: new URLSearchParams({ query, format: "json" }).toString(),
    headers: { Accept: "application/sparql-results+json" },
    perSecond: 1,
    label,
  });
  return res.results?.bindings ?? [];
}

const val = (b, k) => b[k]?.value ?? null;
const qid = (uri) => (uri ? uri.split("/").pop() : null);

/** "Point(-82.684 41.482)" → decimal degrees. */
function parsePoint(wkt) {
  const m = wkt?.match(/Point\(\s*(-?[\d.]+)\s+(-?[\d.]+)\s*\)/i);
  if (!m) return { latitude: null, longitude: null };
  return { longitude: round(Number(m[1]), 6), latitude: round(Number(m[2]), 6) };
}

const yearOf = (iso) => {
  const m = String(iso ?? "").match(/^(-?\d{4})/);
  return m ? Number(m[1]) : null;
};

/** SPARQL returns one row per attribute combination; fold to one row per item. */
function collapse(bindings, build) {
  const byId = new Map();
  for (const b of bindings) {
    const id = qid(val(b, "item"));
    if (!id) continue;
    const next = build(b, id);
    const prev = byId.get(id);
    if (!prev) {
      byId.set(id, next);
      continue;
    }
    // Keep the first non-null value seen for each field.
    for (const [k, v] of Object.entries(next)) {
      if (prev[k] == null && v != null) prev[k] = v;
    }
  }
  return [...byId.values()];
}

export async function fetchCoasters({ log = console.log } = {}) {
  const rows = await sparql(COASTER_QUERY, "wikidata coasters");
  const coasters = collapse(rows, (b, id) => {
    const { latitude, longitude } = parsePoint(val(b, "coord"));
    return {
      sourceId: id,
      name: val(b, "itemLabel"),
      parkName: val(b, "parkLabel"),
      manufacturer: val(b, "makerLabel"),
      heightM: val(b, "height") ? round(Number(val(b, "height")), 1) : null,
      speedKmh: val(b, "speed") ? round(Number(val(b, "speed")), 1) : null,
      lengthM: val(b, "length") ? round(Number(val(b, "length")), 1) : null,
      openedYear: yearOf(val(b, "inception")),
      rcdbNumber: val(b, "rcdb") ? Number(val(b, "rcdb")) : null,
      latitude,
      longitude,
    };
  }).filter((c) => c.name && !/^Q\d+$/.test(c.name));

  log(`  ${coasters.length} coasters from Wikidata`);
  return coasters;
}

export async function fetchParks({ log = console.log } = {}) {
  const rows = await sparql(PARK_QUERY, "wikidata parks");
  const parks = collapse(rows, (b, id) => {
    const { latitude, longitude } = parsePoint(val(b, "coord"));
    return {
      sourceId: id,
      name: val(b, "itemLabel"),
      country: val(b, "countryLabel"),
      openedYear: yearOf(val(b, "inception")),
      latitude,
      longitude,
    };
  }).filter((p) => p.name && !/^Q\d+$/.test(p.name));

  log(`  ${parks.length} parks from Wikidata`);
  return parks;
}
