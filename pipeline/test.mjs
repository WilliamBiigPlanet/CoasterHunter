// Pipeline unit tests. Run with `node --test test.mjs`.
//
// These cover the parts most likely to silently corrupt the database: name
// matching (a wrong merge shows a user the wrong ride's stats), unit conversion,
// and infobox parsing.

import { test } from "node:test";
import assert from "node:assert/strict";

import { bestSimilarity, nameVariants, normName, similarity } from "./src/util/text.mjs";
import { durationToSeconds, feetToMetres, inchesToCm, mphToKmh, preferMetric } from "./src/util/units.mjs";
import { parseInfobox, toCoaster, kindFromType } from "./src/sources/wikipedia.mjs";
import { classify } from "./src/classify.mjs";
import { haversine, matchAttraction, resolvePark, buildParkIndex } from "./src/match.mjs";

// --------------------------------------------------------------------- text ---

test("normName strips articles, punctuation, diacritics and ride-type noise", () => {
  assert.equal(normName("The Nemesis: Reborn (roller coaster)"), "nemesis reborn");
  assert.equal(normName("Parc Astérix"), "parc asterix");
  assert.equal(normName("Kærlighedstunnelen"), "kaerlighedstunnelen");
  assert.equal(normName("Rock 'n' Roller Coaster"), "rock n");
  assert.equal(normName(""), "");
  assert.equal(normName(null), "");
});

test("similarity is 1 for identical and low for unrelated names", () => {
  assert.equal(similarity("millennium force", "millennium force"), 1);
  assert.ok(similarity("millennium force", "magnum xl 200") < 0.3);
});

test("nameVariants recovers sponsor prefixes, subtitles and spacing", () => {
  assert.ok(nameVariants("SUPERMAN: Ride of Steel").includes("ride of steel"));
  assert.ok(nameVariants("Loch Ness Monster: The Legend Lives On").includes("loch ness monster"));
  assert.ok(nameVariants("Powder Keg").includes("powderkeg"));
  assert.ok(nameVariants("Le Vampire").includes("vampire"));
  assert.ok(nameVariants("BATWING Coaster").includes("batwing"));
});

test("bestSimilarity matches the same ride written differently", () => {
  const pairs = [
    ["Ride of Steel", "SUPERMAN: Ride of Steel"],
    ["Loch Ness Monster", "Loch Ness Monster: The Legend Lives On"],
    ["Batwing", "BATWING Coaster"],
    ["Big Bad Wolf", "The Big Bad Wolf: The Wolf's Revenge"],
    ["Powder Keg", "PowderKeg"],
    ["Le Vampire", "Vampire"],
  ];
  for (const [a, b] of pairs) {
    assert.ok(bestSimilarity(a, b) >= 0.86, `expected "${a}" to match "${b}"`);
  }
});

test("bestSimilarity keeps genuinely different rides apart", () => {
  // Valleyfair really does have both. Merging them would show a user the wrong
  // ride's height, which is the single worst failure mode in this pipeline.
  assert.ok(bestSimilarity("Mild Thing", "Wild Thing") < 0.86);
  assert.ok(bestSimilarity("Son of Beast", "The Beast") < 0.86);
  assert.ok(bestSimilarity("WildCat", "Wild Mouse") < 0.86);
  assert.ok(bestSimilarity("Fujiyama", "FUJIYAMA WALK") < 0.86);
});

// -------------------------------------------------------------------- units ---

test("imperial to metric conversion", () => {
  assert.equal(feetToMetres(310), 94.5);
  assert.equal(mphToKmh(93), 149.7);
  assert.equal(inchesToCm(48), 122);
  assert.equal(feetToMetres(null), null);
});

test("preferMetric uses the metric field when present", () => {
  assert.equal(preferMetric("94 m", "310 ft", feetToMetres), 94);
  assert.equal(preferMetric(null, "310 ft", feetToMetres), 94.5);
  assert.equal(preferMetric(null, null, feetToMetres), null);
});

test("duration parsing handles clock, prose and bare seconds", () => {
  assert.equal(durationToSeconds("2:20"), 140);
  assert.equal(durationToSeconds("1 minute 30 seconds"), 90);
  assert.equal(durationToSeconds("165"), 165);
  assert.equal(durationToSeconds(null), null);
});

// ---------------------------------------------------------------- wikitext ---

const MILLENNIUM_FORCE = `
{{Infobox roller coaster
| name = Millennium Force
| location = Cedar Point
| section = Millennium Midway
| coordinates = {{coord|41|28|54|N|82|41|17|W|region:US-OH_type:landmark}}
| status = Operating
| opened = {{start date|2000|5|13}}
| type = Steel
| manufacturer = [[Intamin]]
| designer = [[Werner Stengel]]
| model = [[Roller coaster#By height|Giga Coaster]]
| height_ft = 310
| drop_ft = 300
| length_ft = 6595
| speed_mph = 93
| inversions = 0
| duration = 2:20
| gforce = 4.5
| restriction_in = 48
| trains = 3<!-- three trains -->
| rcdb_number = 594
}}
`;

test("infobox parsing extracts a complete spec sheet", () => {
  const fields = parseInfobox(MILLENNIUM_FORCE);
  assert.ok(fields, "infobox should parse");
  const c = toCoaster("Millennium Force", fields);

  assert.equal(c.name, "Millennium Force");
  assert.equal(c.parkName, "Cedar Point");
  assert.equal(c.areaName, "Millennium Midway");
  assert.equal(c.status, "operating");
  assert.equal(c.openedYear, 2000);
  assert.equal(c.manufacturer, "Intamin");
  assert.equal(c.designer, "Werner Stengel");
  assert.equal(c.model, "Giga Coaster", "piped wikilinks should resolve to the label");
  assert.equal(c.heightM, 94.5);
  assert.equal(c.dropM, 91.4);
  assert.equal(c.speedKmh, 149.7);
  assert.equal(c.inversions, 0);
  assert.equal(c.durationSeconds, 140);
  assert.equal(c.maxGForce, 4.5);
  assert.equal(c.heightRestrictionCm, 122);
  assert.equal(c.trains, 3, "HTML comments should not break number parsing");
  assert.equal(c.rcdbNumber, 594);
  assert.equal(c.kind, "coaster");
});

test("DMS coordinates convert to signed decimal degrees", () => {
  const c = toCoaster("Millennium Force", parseInfobox(MILLENNIUM_FORCE));
  assert.ok(Math.abs(c.latitude - 41.4817) < 0.001);
  assert.ok(Math.abs(c.longitude - -82.6881) < 0.001, "west should be negative");
});

test("parseInfobox returns null when the template is absent", () => {
  assert.equal(parseInfobox("Just some prose with no infobox."), null);
});

test("kindFromType reads the general attraction infobox type field", () => {
  assert.equal(kindFromType(["Dark ride"]), "dark");
  assert.equal(kindFromType(["Water ride", "Flume"]), "water");
  assert.equal(kindFromType(["Steel roller coaster"]), "coaster");
  assert.equal(kindFromType([]), null);
});

// ----------------------------------------------------------------- classify ---

test("classify handles several languages", () => {
  assert.equal(classify("Congo River Rapids"), "water");
  assert.equal(classify("Wilde Maus"), "coaster");
  assert.equal(classify("海盗船"), "flat");           // pirate ship
  assert.equal(classify("梦幻转马"), "flat");          // carousel
  assert.equal(classify("Geisterbahn"), "dark");
  assert.equal(classify("Skyride to Forbidden Valley"), "transport");
  assert.equal(classify("Anything Live Show", { entityType: "SHOW" }), "show");
});

test("classify does not mistake a riverboat for a water ride", () => {
  assert.equal(classify("Mississippi Riverboat"), "transport");
  assert.equal(classify("Rambling River"), "water");
});

test("classify returns other rather than guessing", () => {
  assert.equal(classify("Whiskers Harbour Game Booths"), "other");
});

// -------------------------------------------------------------------- match ---

test("haversine measures real distances", () => {
  const cedarPoint = { latitude: 41.4826, longitude: -82.6842 };
  const millenniumForce = { latitude: 41.48194, longitude: -82.68651 };
  const d = haversine(cedarPoint, millenniumForce);
  assert.ok(d > 100 && d < 400, `expected a few hundred metres, got ${d}`);
  assert.equal(haversine(cedarPoint, { latitude: null, longitude: null }), null);
});

test("resolvePark tolerates Resort suffixes and destination names", () => {
  const index = buildParkIndex([
    { sourceId: "p1", name: "Alton Towers", destinationName: "Alton Towers Resort" },
    { sourceId: "p2", name: "Cedar Point", destinationName: "Cedar Point" },
  ]);
  assert.equal(resolvePark(index, "Alton Towers Resort").sourceId, "p1");
  assert.equal(resolvePark(index, "Cedar Point").sourceId, "p2");
  assert.equal(resolvePark(index, "Somewhere That Does Not Exist At All"), null);
});

test("matchAttraction refuses to choose between two equally good candidates", () => {
  const candidates = [
    { sourceId: "a", name: "The Bat" },
    { sourceId: "b", name: "The Bat" },
  ];
  const result = matchAttraction(candidates, { name: "The Bat" });
  assert.equal(result.attraction, null);
  assert.equal(result.reason, "ambiguous");
});

test("matchAttraction uses coordinates to break a tie", () => {
  const candidates = [
    { sourceId: "far", name: "Thunder", latitude: 41.0, longitude: -82.0 },
    { sourceId: "near", name: "Thunder Run", latitude: 41.4819, longitude: -82.6865 },
  ];
  const result = matchAttraction(candidates, {
    name: "Thunder Run",
    latitude: 41.4820,
    longitude: -82.6866,
  });
  assert.equal(result.attraction?.sourceId, "near");
});
