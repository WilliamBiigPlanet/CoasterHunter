// English Wikipedia — the richest free source of coaster spec sheets.
// {{Infobox roller coaster}} carries height, drop, length, speed, inversions,
// g-force, height restriction, train layout and accessibility flags.
//
// Licence note: we extract FACTS only (numbers, dates, manufacturer names).
// Facts are not copyrightable. We never take prose or images, and every record
// keeps an attribution row pointing back at the article.

import { getJSON } from "../util/http.mjs";
import { titleToName } from "../util/text.mjs";
import {
  durationToSeconds,
  feetToMetres,
  firstNumber,
  inchesToCm,
  mphToKmh,
  preferMetric,
  round,
} from "../util/units.mjs";

const API = "https://en.wikipedia.org/w/api.php";
const COASTER_TEMPLATE = "Template:Infobox roller coaster";
const ATTRACTION_TEMPLATE = "Template:Infobox attraction";
const RATE = 8;

export const SOURCE = {
  key: "wikipedia",
  name: "Wikipedia",
  url: "https://en.wikipedia.org",
  licence: "CC BY-SA 4.0 (factual data extracted; no prose reused)",
};

/** Every mainspace article transcluding a given infobox template. */
export async function listArticles(TEMPLATE, { log = console.log } = {}) {
  const titles = [];
  let cont = null;

  do {
    const url =
      `${API}?action=query&list=embeddedin&eititle=${encodeURIComponent(TEMPLATE)}` +
      `&einamespace=0&eilimit=500&format=json&formatversion=2` +
      (cont ? `&eicontinue=${encodeURIComponent(cont)}` : "");
    const res = await getJSON(url, { perSecond: RATE, label: "wp article list" });
    for (const p of res.query?.embeddedin ?? []) titles.push(p.title);
    cont = res.continue?.eicontinue ?? null;
  } while (cont);

  log(`  ${titles.length} articles transclude ${TEMPLATE}`);
  return titles;
}

/** MediaWiki accepts 50 titles per revisions query, so 888 articles is ~18 calls. */
export async function fetchWikitext(titles, { log = console.log } = {}) {
  const out = new Map();
  const batches = [];
  for (let i = 0; i < titles.length; i += 50) batches.push(titles.slice(i, i + 50));

  for (const [i, batch] of batches.entries()) {
    const url =
      `${API}?action=query&prop=revisions&rvprop=content&rvslots=main` +
      `&titles=${encodeURIComponent(batch.join("|"))}` +
      `&format=json&formatversion=2`;
    const res = await getJSON(url, { perSecond: RATE, label: `wikitext batch ${i}` });
    for (const page of res.query?.pages ?? []) {
      const text = page.revisions?.[0]?.slots?.main?.content;
      if (text) out.set(page.title, text);
    }
    log(`  wikitext ${Math.min((i + 1) * 50, titles.length)}/${titles.length}`);
  }
  return out;
}

// ---------------------------------------------------------------- wikitext ---

/** Extract the named template's body, respecting nested braces. */
function extractTemplate(wikitext, templateName) {
  const start = wikitext.search(
    new RegExp(`\\{\\{\\s*${templateName}`, "i"),
  );
  if (start === -1) return null;

  let depth = 0;
  for (let i = start; i < wikitext.length - 1; i++) {
    if (wikitext[i] === "{" && wikitext[i + 1] === "{") {
      depth++;
      i++;
    } else if (wikitext[i] === "}" && wikitext[i + 1] === "}") {
      depth--;
      i++;
      if (depth === 0) return wikitext.slice(start + 2, i - 1);
    }
  }
  return null;
}

/** Split on pipes that are at the top level — not inside {{ }} or [[ ]]. */
function splitParams(body) {
  const parts = [];
  let depth = 0;
  let buf = "";
  for (let i = 0; i < body.length; i++) {
    const two = body.slice(i, i + 2);
    if (two === "{{" || two === "[[") {
      depth++;
      buf += two;
      i++;
      continue;
    }
    if (two === "}}" || two === "]]") {
      depth--;
      buf += two;
      i++;
      continue;
    }
    if (body[i] === "|" && depth === 0) {
      parts.push(buf);
      buf = "";
      continue;
    }
    buf += body[i];
  }
  parts.push(buf);
  return parts;
}

/** Reduce a wikitext value to plain text, keeping the numbers intact. */
function cleanValue(raw) {
  let s = raw;

  s = s.replace(/<!--[\s\S]*?-->/g, "");
  s = s.replace(/<ref[^>]*\/>/gi, "");
  s = s.replace(/<ref[^>]*>[\s\S]*?<\/ref>/gi, "");
  s = s.replace(/<br\s*\/?>/gi, ", ");
  s = s.replace(/<[^>]+>/g, "");

  // {{convert|310|ft|m|adj=on}} → "310 ft"
  s = s.replace(/\{\{\s*convert\s*\|([^|}]+)\|([^|}]+)[^}]*\}\}/gi, "$1 $2");
  // {{start date|2000|5|13}} / {{end date|...}} → ISO-ish
  s = s.replace(
    /\{\{\s*(?:start|end)[ _]date[^|}]*\|\s*(\d{4})(?:\|\s*(\d{1,2}))?(?:\|\s*(\d{1,2}))?[^}]*\}\}/gi,
    (_, y, m, d) =>
      [y, m?.padStart(2, "0"), d?.padStart(2, "0")].filter(Boolean).join("-"),
  );
  // {{coord|41|28|54|N|82|41|17|W|...}} — handled separately, drop here
  s = s.replace(/\{\{\s*coord[^}]*\}\}/gi, "");
  // Any remaining template: keep its last positional argument, usually the label
  s = s.replace(/\{\{[^{}]*\}\}/g, (m) => {
    const inner = m.slice(2, -2).split("|");
    return inner.length > 1 ? inner[inner.length - 1] : "";
  });

  // [[Target|Label]] → Label ; [[Target]] → Target
  s = s.replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, "$2");
  s = s.replace(/\[\[([^\]]+)\]\]/g, "$1");
  s = s.replace(/\[https?:\/\/\S+\s+([^\]]+)\]/g, "$1");
  s = s.replace(/\[https?:\/\/\S+\]/g, "");

  s = s.replace(/'''?/g, "");
  s = s.replace(/&nbsp;/gi, " ");
  s = s.replace(/&amp;/gi, "&");
  s = s.replace(/\s+/g, " ").trim();
  s = s.replace(/^[,;]+|[,;]+$/g, "").trim();
  return s;
}

/** {{coord|41|28|54|N|82|41|17|W}} or {{coord|41.48|-82.68}} → decimal degrees. */
function parseCoord(raw) {
  const m = raw?.match(/\{\{\s*coord\s*\|([^}]*)\}\}/i);
  if (!m) return { latitude: null, longitude: null };
  const args = m[1]
    .split("|")
    .map((a) => a.trim())
    .filter((a) => a && !a.includes("="));

  const dms = (deg, min, sec, hemi) => {
    const v = Number(deg) + Number(min ?? 0) / 60 + Number(sec ?? 0) / 3600;
    return /[SW]/i.test(hemi) ? -v : v;
  };

  if (/^[NS]$/i.test(args[3] ?? "") && /^[EW]$/i.test(args[7] ?? "")) {
    return {
      latitude: round(dms(args[0], args[1], args[2], args[3]), 6),
      longitude: round(dms(args[4], args[5], args[6], args[7]), 6),
    };
  }
  if (/^[NS]$/i.test(args[2] ?? "") && /^[EW]$/i.test(args[5] ?? "")) {
    return {
      latitude: round(dms(args[0], args[1], null, args[2]), 6),
      longitude: round(dms(args[3], args[4], null, args[5]), 6),
    };
  }
  const lat = Number(args[0]);
  const lon = Number(args[1]);
  return Number.isFinite(lat) && Number.isFinite(lon)
    ? { latitude: round(lat, 6), longitude: round(lon, 6) }
    : { latitude: null, longitude: null };
}

/** Parse the infobox into a flat key→cleaned-value map. */
export function parseInfobox(wikitext, pattern = "Infobox roller ?coaster") {
  const body = extractTemplate(wikitext, pattern);
  if (!body) return null;

  const fields = {};
  const parts = splitParams(body);
  for (const part of parts.slice(1)) {
    const eq = part.indexOf("=");
    if (eq === -1) continue;
    const key = part.slice(0, eq).trim().toLowerCase();
    const rawValue = part.slice(eq + 1);
    if (!key) continue;
    fields[key] = { raw: rawValue, value: cleanValue(rawValue) };
  }
  return fields;
}

const STATUS_MAP = [
  [/removed|demolish|defunct|closed|sbno|standing but not operating/i, "defunct"],
  [/relocat/i, "relocated"],
  [/under construction|announced|planned/i, "planned"],
  [/operating|open/i, "operating"],
];

function mapStatus(raw) {
  if (!raw) return null;
  for (const [re, val] of STATUS_MAP) if (re.test(raw)) return val;
  return null;
}

function year(value) {
  const m = String(value ?? "").match(/\b(1[89]\d{2}|20\d{2})\b/);
  return m ? Number(m[1]) : null;
}

/** Turn a raw infobox into a normalised coaster record. */
/** The general attraction infobox carries a free-text `type` we can classify on. */
const TYPE_HINTS = [
  [/roller ?coaster|coaster/i, "coaster"],
  [/water|flume|rapids|splash|shoot/i, "water"],
  [/dark ?ride|haunted|walk-?through|simulator|motion|theatre ride|omnimover/i, "dark"],
  [/show|theatre|theater|spectacular|cinema|film/i, "show"],
  [/train|railway|railroad|monorail|transport|skyway|gondola/i, "transport"],
  [/flat ?ride|carousel|wheel|drop ?tower|swing|spinning|pendulum|tower ride/i, "flat"],
];

export function kindFromType(types) {
  const joined = (types ?? []).filter(Boolean).join(" ");
  if (!joined) return null;
  for (const [re, kind] of TYPE_HINTS) if (re.test(joined)) return kind;
  return null;
}

export function toCoaster(title, fields, { defaultKind = "coaster" } = {}) {
  const get = (k) => fields[k]?.value || null;
  const rawOf = (k) => fields[k]?.raw || null;

  const coord =
    parseCoord(rawOf("coordinates")) ??
    { latitude: null, longitude: null };

  const types = [get("type"), get("type2"), get("type3")].filter(Boolean);
  const kind = defaultKind === "coaster" ? "coaster" : (kindFromType(types) ?? null);

  return {
    articleTitle: title,
    kind,
    theme: get("theme"),
    name: get("name") || titleToName(title),
    previousNames: get("previousnames"),
    parkName: get("location"),
    areaName: get("section"),

    status: mapStatus(get("status")) ?? (get("closed") ? "defunct" : "operating"),
    openedYear: year(get("opened")) ?? year(get("year")) ?? year(get("soft_opened")),
    closedYear: year(get("closed")),

    types,
    trackType: get("track"),
    liftType: get("lift"),
    manufacturer: get("manufacturer"),
    designer: get("designer"),
    model: get("model"),

    heightM: preferMetric(get("height_m"), get("height_ft"), feetToMetres),
    dropM: preferMetric(get("drop_m"), get("drop_ft"), feetToMetres),
    lengthM: preferMetric(get("length_m"), get("length_ft"), feetToMetres),
    speedKmh: preferMetric(get("speed_km/h"), get("speed_mph"), mphToKmh),
    inversions: firstNumber(get("inversions")),
    durationSeconds: durationToSeconds(get("duration")),
    maxAngleDeg: firstNumber(get("angle")),
    maxGForce: firstNumber(get("gforce")),
    capacityPerHour: firstNumber(get("capacity")),
    heightRestrictionCm:
      preferMetric(get("restriction_cm"), get("restriction_in"), inchesToCm),

    trains: firstNumber(get("trains")),
    carsPerTrain: firstNumber(get("carspertrain")),
    rowsPerCar: firstNumber(get("rowspercar")),
    ridersPerRow: firstNumber(get("ridersperrow")),

    singleRider: /yes|available/i.test(get("single_rider") ?? "") || null,
    wheelchairAccessible: /yes|available/i.test(get("accessible") ?? "") || null,
    mustTransfer: /yes|must transfer/i.test(get("transfer_accessible") ?? "") || null,

    rcdbNumber: firstNumber(get("rcdb_number")),
    latitude: coord.latitude,
    longitude: coord.longitude,
  };
}

async function fetchFromTemplate(template, pattern, defaultKind, log) {
  const titles = await listArticles(template, { log });
  const wikitext = await fetchWikitext(titles, { log });

  const records = [];
  let noInfobox = 0;

  for (const [title, text] of wikitext) {
    const fields = parseInfobox(text, pattern);
    if (!fields) {
      noInfobox++;
      continue;
    }
    records.push(toCoaster(title, fields, { defaultKind }));
  }

  log(`  parsed ${records.length} records (${noInfobox} had no parsable infobox)`);
  return records;
}

/** Roller coasters — the richest spec sheets Wikipedia has. */
export async function fetchCoasters({ log = console.log } = {}) {
  return fetchFromTemplate(COASTER_TEMPLATE, "Infobox roller ?coaster", "coaster", log);
}

/** Dark rides, flat rides, water rides and shows, via the general infobox. */
export async function fetchAttractions({ log = console.log } = {}) {
  return fetchFromTemplate(ATTRACTION_TEMPLATE, "Infobox attraction", "attraction", log);
}
