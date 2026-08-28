// Writes the seed database and the coverage report.
//
// The coverage report is a deliverable, not a nicety: it is how we decide
// whether the free sources are good enough to launch on, and it is the work
// queue for manual overrides.

import { DatabaseSync } from "node:sqlite";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { normName } from "./util/text.mjs";
import { classify } from "./classify.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(HERE, "..", "out");

const SPEC_FIELDS = [
  "height_m", "drop_m", "length_m", "speed_kmh", "inversions",
  "duration_seconds", "max_angle_deg", "max_g_force", "height_restriction_cm",
  "opened_year", "manufacturer_id", "model_id", "designer",
];

export function emit({ destinations, parks, attractions, specsByAttraction,
                       wikidataParks, sources, unmatched, review, log = console.log }) {
  mkdirSync(OUT_DIR, { recursive: true });
  const dbPath = join(OUT_DIR, "coasterhunter-seed.sqlite");
  rmSync(dbPath, { force: true });

  const db = new DatabaseSync(dbPath);
  db.exec(readFileSync(join(HERE, "schema.sql"), "utf8"));

  const ins = (sql) => db.prepare(sql);
  const q = {
    meta: ins("INSERT INTO meta (key,value) VALUES (?,?)"),
    source: ins("INSERT INTO sources (key,name,url,licence) VALUES (?,?,?,?)"),
    dest: ins("INSERT OR IGNORE INTO destinations (id,name,slug) VALUES (?,?,?)"),
    park: ins(`INSERT INTO parks
      (id,destination_id,name,name_norm,country,latitude,longitude,timezone,opened_year,external_id)
      VALUES (?,?,?,?,?,?,?,?,?,?)`),
    area: ins("INSERT OR IGNORE INTO park_areas (park_id,name) VALUES (?,?)"),
    areaId: ins("SELECT id FROM park_areas WHERE park_id=? AND name=?"),
    maker: ins("INSERT OR IGNORE INTO manufacturers (name,name_norm) VALUES (?,?)"),
    makerId: ins("SELECT id FROM manufacturers WHERE name=?"),
    model: ins("INSERT OR IGNORE INTO models (manufacturer_id,name) VALUES (?,?)"),
    modelId: ins("SELECT id FROM models WHERE manufacturer_id IS ? AND name=?"),
    attr: ins(`INSERT INTO attractions
      (id,park_id,area_id,name,name_norm,kind,status,latitude,longitude,external_id,has_specs)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)`),
    spec: ins(`INSERT INTO attraction_specs
      (attraction_id,manufacturer_id,model_id,designer,track_type,lift_type,
       opened_year,closed_year,height_m,drop_m,length_m,speed_kmh,inversions,
       duration_seconds,max_angle_deg,max_g_force,capacity_per_hour,
       height_restriction_cm,trains,cars_per_train,rows_per_car,riders_per_row,
       single_rider,wheelchair_accessible,must_transfer,previous_names)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`),
    ext: ins("INSERT OR IGNORE INTO external_ids (entity_kind,entity_id,source_key,source_id) VALUES (?,?,?,?)"),
    attrib: ins("INSERT OR IGNORE INTO attributions (entity_kind,entity_id,source_key,url) VALUES (?,?,?,?)"),
  };

  db.exec("BEGIN");

  for (const s of sources) q.source.run(s.key, s.name, s.url, s.licence);
  q.meta.run("schema_version", "1");
  q.meta.run("built_at", new Date().toISOString());

  for (const d of destinations) q.dest.run(d.id, d.name, d.slug ?? null);

  // Wikidata parks give us country and opening year where names line up.
  const wdByNorm = new Map();
  for (const p of wikidataParks ?? []) {
    const key = normName(p.name);
    if (key && !wdByNorm.has(key)) wdByNorm.set(key, p);
  }

  for (const p of parks) {
    const norm = normName(p.name);
    const wd = wdByNorm.get(norm);
    q.park.run(
      p.sourceId, p.destinationId, p.name, norm,
      wd?.country ?? null, p.latitude, p.longitude, p.timezone,
      wd?.openedYear ?? null, p.externalId,
    );
    q.ext.run("park", p.sourceId, "themeparks", p.sourceId);
    q.attrib.run("park", p.sourceId, "themeparks", "https://themeparks.wiki");
    if (wd) {
      q.ext.run("park", p.sourceId, "wikidata", wd.sourceId);
      q.attrib.run("park", p.sourceId, "wikidata", `https://www.wikidata.org/wiki/${wd.sourceId}`);
    }
  }

  const makerCache = new Map();
  function manufacturerId(name) {
    if (!name) return null;
    const clean = name.trim();
    if (makerCache.has(clean)) return makerCache.get(clean);
    q.maker.run(clean, normName(clean));
    const id = q.makerId.get(clean)?.id ?? null;
    makerCache.set(clean, id);
    return id;
  }

  function modelId(makerId, name) {
    if (!name) return null;
    q.model.run(makerId, name.trim());
    return q.modelId.get(makerId, name.trim())?.id ?? null;
  }

  const areaCache = new Map();
  function areaId(parkId, name) {
    if (!name) return null;
    const key = `${parkId}::${name}`;
    if (areaCache.has(key)) return areaCache.get(key);
    q.area.run(parkId, name);
    const id = q.areaId.get(parkId, name)?.id ?? null;
    areaCache.set(key, id);
    return id;
  }

  const bool = (v) => (v == null ? null : v ? 1 : 0);
  let specCount = 0;

  for (const a of attractions) {
    const spec = specsByAttraction.get(a.sourceId) ?? null;
    // A spec record's own kind is authoritative; otherwise fall back to
    // classifying the name.
    const kind =
      spec?.kind ??
      classify(a.name, { entityType: a.entityType });

    const area = spec?.areaName ? areaId(a.parkSourceId, spec.areaName) : null;

    q.attr.run(
      a.sourceId, a.parkSourceId, area, a.name, normName(a.name),
      kind, spec?.status ?? "operating",
      a.latitude ?? spec?.latitude ?? null,
      a.longitude ?? spec?.longitude ?? null,
      a.externalId, spec ? 1 : 0,
    );
    q.ext.run("attraction", a.sourceId, "themeparks", a.sourceId);
    q.attrib.run("attraction", a.sourceId, "themeparks", "https://themeparks.wiki");

    if (!spec) continue;
    specCount++;

    const mkId = manufacturerId(spec.manufacturer);
    q.spec.run(
      a.sourceId, mkId, modelId(mkId, spec.model), spec.designer ?? null,
      spec.trackType ?? null, spec.liftType ?? null,
      spec.openedYear ?? null, spec.closedYear ?? null,
      spec.heightM ?? null, spec.dropM ?? null, spec.lengthM ?? null,
      spec.speedKmh ?? null, spec.inversions ?? null,
      spec.durationSeconds ?? null, spec.maxAngleDeg ?? null,
      spec.maxGForce ?? null, spec.capacityPerHour ?? null,
      spec.heightRestrictionCm ?? null, spec.trains ?? null,
      spec.carsPerTrain ?? null, spec.rowsPerCar ?? null, spec.ridersPerRow ?? null,
      bool(spec.singleRider), bool(spec.wheelchairAccessible), bool(spec.mustTransfer),
      spec.previousNames ?? null,
    );

    if (spec.articleTitle) {
      q.ext.run("attraction", a.sourceId, "wikipedia", spec.articleTitle);
      q.attrib.run("attraction", a.sourceId, "wikipedia",
        `https://en.wikipedia.org/wiki/${encodeURIComponent(spec.articleTitle.replace(/ /g, "_"))}`);
    }
    if (spec.wikidataId) {
      q.ext.run("attraction", a.sourceId, "wikidata", spec.wikidataId);
      q.attrib.run("attraction", a.sourceId, "wikidata",
        `https://www.wikidata.org/wiki/${spec.wikidataId}`);
    }
    if (spec.rcdbNumber) {
      q.ext.run("attraction", a.sourceId, "rcdb", String(spec.rcdbNumber));
    }
  }

  db.exec("COMMIT");

  const report = buildCoverage(db, { specCount, unmatched, review });
  writeFileSync(join(OUT_DIR, "coverage.md"), report.markdown);
  writeFileSync(
    join(OUT_DIR, "review-queue.json"),
    JSON.stringify(review, null, 2),
  );

  assertIntegrity(db);
  db.close();

  log(`  wrote ${dbPath}`);
  return report.stats;
}

// --------------------------------------------------------------- integrity ---

function assertIntegrity(db) {
  const problems = [];
  const one = (sql) => Object.values(db.prepare(sql).get())[0];

  const orphanAttrs = one(
    "SELECT count(*) FROM attractions a LEFT JOIN parks p ON p.id=a.park_id WHERE p.id IS NULL");
  if (orphanAttrs > 0) problems.push(`${orphanAttrs} attractions reference a missing park`);

  const unattributedParks = one(
    "SELECT count(*) FROM parks p WHERE NOT EXISTS (SELECT 1 FROM attributions x WHERE x.entity_kind='park' AND x.entity_id=p.id)");
  if (unattributedParks > 0) problems.push(`${unattributedParks} parks have no attribution row`);

  const unattributedAttrs = one(
    "SELECT count(*) FROM attractions a WHERE NOT EXISTS (SELECT 1 FROM attributions x WHERE x.entity_kind='attraction' AND x.entity_id=a.id)");
  if (unattributedAttrs > 0) problems.push(`${unattributedAttrs} attractions have no attribution row`);

  const specsWithoutAttraction = one(
    "SELECT count(*) FROM attraction_specs s LEFT JOIN attractions a ON a.id=s.attraction_id WHERE a.id IS NULL");
  if (specsWithoutAttraction > 0) problems.push(`${specsWithoutAttraction} spec rows have no attraction`);

  const parks = one("SELECT count(*) FROM parks");
  if (parks < 150) problems.push(`only ${parks} parks — expected at least 150`);
  const attrs = one("SELECT count(*) FROM attractions");
  if (attrs < 5000) problems.push(`only ${attrs} attractions — expected at least 5000`);

  if (problems.length) {
    throw new Error(`seed database failed integrity checks:\n  - ${problems.join("\n  - ")}`);
  }
}

// ---------------------------------------------------------------- coverage ---

function buildCoverage(db, { specCount, unmatched, review }) {
  const all = (sql, ...p) => db.prepare(sql).all(...p);
  const one = (sql) => Object.values(db.prepare(sql).get())[0];

  const stats = {
    destinations: one("SELECT count(*) FROM destinations"),
    parks: one("SELECT count(*) FROM parks"),
    attractions: one("SELECT count(*) FROM attractions"),
    coasters: one("SELECT count(*) FROM attractions WHERE kind='coaster'"),
    withSpecs: specCount,
    manufacturers: one("SELECT count(*) FROM manufacturers"),
    unmatched: unmatched.length,
    review: review.length,
  };

  const byKind = all("SELECT kind, count(*) n FROM attractions GROUP BY kind ORDER BY n DESC");
  const withCoords = one("SELECT count(*) FROM attractions WHERE latitude IS NOT NULL");

  const coastersWithSpecs = one(`
    SELECT count(*) FROM attraction_specs s
    JOIN attractions a ON a.id = s.attraction_id WHERE a.kind = 'coaster'`);

  const completeness = SPEC_FIELDS.map((f) => ({
    field: f,
    filled: one(`SELECT count(*) FROM attraction_specs WHERE ${f} IS NOT NULL`),
    coasters: one(`
      SELECT count(*) FROM attraction_specs s
      JOIN attractions a ON a.id = s.attraction_id
      WHERE a.kind = 'coaster' AND s.${f} IS NOT NULL`),
  }));

  const topMakers = all(`
    SELECT m.name, count(*) n FROM attraction_specs s
    JOIN manufacturers m ON m.id = s.manufacturer_id
    GROUP BY m.id ORDER BY n DESC LIMIT 12`);

  const emptiestParks = all(`
    SELECT p.name, count(a.id) n FROM parks p
    LEFT JOIN attractions a ON a.park_id = p.id
    GROUP BY p.id HAVING n = 0 ORDER BY p.name LIMIT 15`);

  const pct = (n, d) => (d ? `${((n / d) * 100).toFixed(1)}%` : "—");

  const md = [
    "# CoasterHunter seed database — coverage report",
    "",
    `Built ${new Date().toISOString()}`,
    "",
    "## Totals",
    "",
    "| | Count |",
    "|---|---:|",
    `| Destinations | ${stats.destinations} |`,
    `| Parks | ${stats.parks} |`,
    `| Attractions | ${stats.attractions} |`,
    `| — with coordinates | ${withCoords} (${pct(withCoords, stats.attractions)}) |`,
    `| Coasters (spec-matched) | ${stats.coasters} |`,
    `| Manufacturers | ${stats.manufacturers} |`,
    "",
    "## Attractions by kind",
    "",
    "| Kind | Count |",
    "|---|---:|",
    ...byKind.map((r) => `| ${r.kind} | ${r.n} |`),
    "",
    "## Spec completeness",
    "",
    `Of ${stats.withSpecs} attractions that matched a spec record, of which`,
    `${coastersWithSpecs} are coasters. Coasters are the column that matters —`,
    "a dark ride has no drop height and never will.",
    "",
    "| Field | All | % | Coasters | % |",
    "|---|---:|---:|---:|---:|",
    ...completeness.map(
      (c) =>
        `| ${c.field} | ${c.filled} | ${pct(c.filled, stats.withSpecs)} | ` +
        `${c.coasters} | ${pct(c.coasters, coastersWithSpecs)} |`,
    ),
    "",
    "## Top manufacturers",
    "",
    "| Manufacturer | Rides |",
    "|---|---:|",
    ...topMakers.map((m) => `| ${m.name} | ${m.n} |`),
    "",
    "## Unresolved",
    "",
    `${stats.unmatched} spec records did not attach to an attraction.`,
    `${stats.review} of those are close enough to be worth a human decision —`,
    "see `out/review-queue.json`, then add entries to `overrides/manual.json`.",
    "",
    "Breakdown by reason:",
    "",
    "| Reason | Count |",
    "|---|---:|",
    ...Object.entries(
      unmatched.reduce((acc, u) => ((acc[u.reason] = (acc[u.reason] ?? 0) + 1), acc), {}),
    ).map(([r, n]) => `| ${r} | ${n} |`),
    "",
    ...(emptiestParks.length
      ? [
          "## Parks with no attractions listed",
          "",
          "These come back empty from the source and need a submission path:",
          "",
          ...emptiestParks.map((p) => `- ${p.name}`),
          "",
        ]
      : []),
    "## Licensing",
    "",
    "Every park and attraction row carries at least one `attributions` row.",
    "OpenStreetMap is deliberately **not** used here — its ODbL share-alike",
    "attaches to derivative databases, so it stays a runtime map-display source only.",
    "",
  ].join("\n");

  return { markdown: md, stats };
}
