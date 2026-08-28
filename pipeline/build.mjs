#!/usr/bin/env node
// CoasterHunter seed pipeline.
//
//   node build.mjs              use the on-disk cache where possible
//   node build.mjs --no-cache   re-fetch everything from source
//
// Produces out/coasterhunter-seed.sqlite, out/coverage.md and
// out/review-queue.json. Exits non-zero if the database fails integrity checks,
// so this is safe to run in CI.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { setCacheEnabled } from "./src/util/http.mjs";
import * as themeparks from "./src/sources/themeparks.mjs";
import * as wikipedia from "./src/sources/wikipedia.mjs";
import * as wikidata from "./src/sources/wikidata.mjs";
import { buildParkIndex, matchAll } from "./src/match.mjs";
import { emit } from "./src/emit.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

const started = Date.now();
const step = (n, label) => console.log(`\n[${n}] ${label}`);
const log = (m) => console.log(m);

if (process.argv.includes("--no-cache")) {
  setCacheEnabled(false);
  console.log("cache disabled — fetching everything fresh");
}

// ---------------------------------------------------------------- 1. fetch ---

step(1, "themeparks.wiki — parks and attraction lists");
const { destinations, parks, attractions } = await themeparks.fetchThemeParks({ log });

step(2, "Wikipedia — coaster spec sheets");
const wpCoasters = await wikipedia.fetchCoasters({ log });

step("2b", "Wikipedia — dark, flat and water ride spec sheets");
const wpAttractions = await wikipedia.fetchAttractions({ log });

step(3, "Wikidata — cross-references and park metadata");
const wdCoasters = await wikidata.fetchCoasters({ log });
const wdParks = await wikidata.fetchParks({ log });

// ---------------------------------------------------------------- 2. match ---

step(4, "resolving spec records to attractions");
const parkIndex = buildParkIndex(parks);

const overridesFile = JSON.parse(
  readFileSync(join(HERE, "overrides", "manual.json"), "utf8"),
);
const overrides = overridesFile.matches ?? {};

// Wikipedia first — it has far richer specs, so it wins any contest for a slot.
const wp = matchAll({ attractions, records: wpCoasters, parkIndex, overrides });
log(`  Wikipedia: ${wp.matches.size} matched, ${wp.unmatched.length} unmatched`);

// Then non-coaster attractions, into the slots coasters did not take.
const afterCoasters = attractions.filter((a) => !wp.matches.has(a.sourceId));
const wpa = matchAll({
  attractions: afterCoasters,
  records: wpAttractions,
  parkIndex,
  overrides,
});
log(`  other attractions: ${wpa.matches.size} matched`);

// Wikidata fills gaps the two Wikipedia passes left, and never overwrites them.
const remaining = afterCoasters.filter((a) => !wpa.matches.has(a.sourceId));
const wd = matchAll({
  attractions: remaining,
  records: wdCoasters.map((c) => ({ ...c, wikidataId: c.sourceId, kind: "coaster" })),
  parkIndex,
  overrides,
});
log(`  Wikidata:  ${wd.matches.size} additional matched`);

// Later passes must not clobber earlier, richer ones.
const specsByAttraction = new Map([...wd.matches, ...wpa.matches, ...wp.matches]);
const unmatched = [...wp.unmatched, ...wpa.unmatched, ...wd.unmatched];
const review = [...wp.review, ...wpa.review, ...wd.review];

// ----------------------------------------------------------------- 3. emit ---

step(5, "writing seed database");
const stats = emit({
  destinations,
  parks,
  attractions,
  specsByAttraction,
  wikidataParks: wdParks,
  sources: [themeparks.SOURCE, wikipedia.SOURCE, wikidata.SOURCE, {
    key: "rcdb",
    name: "Roller Coaster DataBase",
    url: "https://rcdb.com",
    licence: "Reference ID only — no data extracted",
  }],
  unmatched,
  review,
  log,
});

const seconds = ((Date.now() - started) / 1000).toFixed(1);
console.log(`
done in ${seconds}s

  ${stats.parks} parks · ${stats.attractions} attractions · ${stats.coasters} coasters with specs
  ${stats.manufacturers} manufacturers · ${stats.review} records awaiting a human decision

  out/coasterhunter-seed.sqlite
  out/coverage.md
  out/review-queue.json
`);
