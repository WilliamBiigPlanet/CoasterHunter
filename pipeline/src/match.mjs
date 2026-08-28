// Cross-source entity resolution.
//
// themeparks.wiki owns identity: if a ride is in a park's attraction list, that
// is the record we log against. Wikipedia and Wikidata attach specs to it.
//
// A wrong merge is worse than a missing spec — a user seeing Nemesis's stats on
// Oblivion's page loses trust immediately, whereas a blank height is merely a
// gap that a submission can fill. So the confidence bar is deliberately high and
// anything ambiguous is written to the review queue instead of being guessed.

import { bestSimilarity, normName, similarity } from "./util/text.mjs";

const NAME_THRESHOLD = 0.86;      // dice coefficient for a confident name match
const AMBIGUOUS_MARGIN = 0.06;    // runner-up this close means we don't decide
const PARK_THRESHOLD = 0.62;      // parks are named loosely across sources
const COORD_METRES = 400;         // rides in the same park sit well inside this

/** Great-circle distance in metres. */
export function haversine(a, b) {
  if (a?.latitude == null || b?.latitude == null) return null;
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.latitude - a.latitude);
  const dLon = toRad(b.longitude - a.longitude);
  const lat1 = toRad(a.latitude);
  const lat2 = toRad(b.latitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/**
 * Resolve which themeparks park a Wikipedia/Wikidata record's free-text park
 * name refers to. Wikipedia writes "Alton Towers Resort", themeparks says
 * "Alton Towers"; both should land on the same park.
 */
export function buildParkIndex(parks) {
  return parks.map((p) => ({
    park: p,
    norm: normName(p.name),
    normDest: normName(p.destinationName),
  }));
}

export function resolvePark(parkIndex, freeTextName) {
  const target = normName(freeTextName);
  if (!target) return null;

  let best = null;
  let bestScore = 0;

  for (const entry of parkIndex) {
    const score = Math.max(
      bestSimilarity(freeTextName, entry.park.name),
      // "Cedar Point" the destination vs "Cedar Point" the park
      bestSimilarity(freeTextName, entry.park.destinationName) * 0.95,
      // "Alton Towers Resort" contains "Alton Towers"
      target.includes(entry.norm) || entry.norm.includes(target) ? 0.9 : 0,
    );
    if (score > bestScore) {
      bestScore = score;
      best = entry.park;
    }
  }
  return bestScore >= PARK_THRESHOLD ? best : null;
}

/**
 * Match one spec record to an attraction inside a known park.
 * @returns {{ attraction: object|null, score: number, reason: string }}
 */
export function matchAttraction(candidates, record) {
  const target = normName(record.name);
  if (!target || candidates.length === 0) {
    return { attraction: null, score: 0, reason: "no-candidates" };
  }

  const scored = candidates
    .map((a) => {
      let score = bestSimilarity(record.name, a.name);

      // Coordinates are a strong tiebreak when both sides have them.
      const d = haversine(a, record);
      if (d != null) {
        if (d <= COORD_METRES) score = Math.min(1, score + 0.08);
        else if (d > 5000) score -= 0.25; // different park entirely
      }
      return { attraction: a, score };
    })
    .sort((x, y) => y.score - x.score);

  const [best, runnerUp] = scored;

  if (best.score < NAME_THRESHOLD) {
    return { attraction: null, score: best.score, reason: "below-threshold" };
  }
  if (runnerUp && best.score - runnerUp.score < AMBIGUOUS_MARGIN) {
    return { attraction: null, score: best.score, reason: "ambiguous" };
  }
  return { attraction: best.attraction, score: best.score, reason: "matched" };
}

/**
 * Match every spec record against the attraction list.
 * @returns {{ matches: Map<string, object>, unmatched: object[], review: object[] }}
 */
export function matchAll({ attractions, records, parkIndex, overrides = {} }) {
  const byPark = new Map();
  for (const a of attractions) {
    if (!byPark.has(a.parkSourceId)) byPark.set(a.parkSourceId, []);
    byPark.get(a.parkSourceId).push(a);
  }

  const matches = new Map(); // attraction sourceId → record
  const unmatched = [];
  const review = [];
  const takenBy = new Map();

  for (const record of records) {
    const key = record.articleTitle ?? record.sourceId ?? record.name;

    // A manual override always wins.
    if (overrides[key]) {
      if (overrides[key] === null) continue; // explicitly "this has no match"
      matches.set(overrides[key], record);
      takenBy.set(overrides[key], key);
      continue;
    }

    const park = resolvePark(parkIndex, record.parkName);
    if (!park) {
      unmatched.push({ key, name: record.name, parkName: record.parkName, reason: "park-unresolved" });
      continue;
    }

    const result = matchAttraction(byPark.get(park.sourceId) ?? [], record);
    if (!result.attraction) {
      const entry = {
        key,
        name: record.name,
        parkName: record.parkName,
        resolvedPark: park.name,
        reason: result.reason,
        score: Number(result.score.toFixed(3)),
      };
      unmatched.push(entry);
      if (result.reason === "ambiguous" || result.score > 0.7) review.push(entry);
      continue;
    }

    const id = result.attraction.sourceId;
    if (matches.has(id)) {
      review.push({
        key,
        name: record.name,
        resolvedPark: park.name,
        reason: "duplicate-target",
        conflictsWith: takenBy.get(id),
      });
      continue;
    }
    matches.set(id, record);
    takenBy.set(id, key);
  }

  return { matches, unmatched, review };
}
