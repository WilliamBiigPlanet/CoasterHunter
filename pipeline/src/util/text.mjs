// Name handling for cross-source matching. Park and ride names are written
// inconsistently across sources — "Nemesis Reborn", "Nemesis: Reborn",
// "Nemesis (Alton Towers)" — so everything is compared in normalised form.

const NOISE = [
  /\broller ?coaster\b/g,
  /\bthe ride\b/g,
  /\bride\b$/g,
  /\bpresented by .*/g,
  /\bsponsored by .*/g,
];

/** Strip diacritics, punctuation, articles and boilerplate. */
export function normName(input) {
  if (!input) return "";
  let s = String(input)
    .replace(/\u0152/g, "OE").replace(/\u0153/g, "oe")
    .replace(/\u00c6/g, "AE").replace(/\u00e6/g, "ae")
    .replace(/\u00d8/g, "O").replace(/\u00f8/g, "o")
    .replace(/\u00df/g, "ss")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\((?:roller ?coaster|ride|attraction)[^)]*\)/g, " ")
    .replace(/[’']/g, "")
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ");

  for (const re of NOISE) s = s.replace(re, " ");

  s = s.replace(/\s+/g, " ").trim();
  s = s.replace(/^(the|a|an) /, "");
  return s;
}

/** Character trigrams, padded so short names still produce signal. */
function trigrams(s) {
  const padded = `  ${s} `;
  const out = new Set();
  for (let i = 0; i < padded.length - 2; i++) out.add(padded.slice(i, i + 3));
  return out;
}

/** Sørensen–Dice coefficient over trigrams. 1 = identical. */
export function similarity(a, b) {
  if (!a || !b) return 0;
  if (a === b) return 1;
  const A = trigrams(a);
  const B = trigrams(b);
  let shared = 0;
  for (const t of A) if (B.has(t)) shared++;
  return (2 * shared) / (A.size + B.size);
}

/** Wikipedia titles carry disambiguators we don't want in a display name. */
export function titleToName(title) {
  return String(title).replace(/\s*\([^)]*\)\s*$/, "").trim();
}

/**
 * Alternative normalised forms of a name.
 *
 * Sources disagree in predictable ways: sponsor prefixes ("SUPERMAN: Ride of
 * Steel"), marketing subtitles ("Loch Ness Monster: The Legend Lives On"),
 * a trailing "Coaster", spacing ("PowderKeg"), and non-English articles
 * ("Le Vampire"). Comparing every variant against every variant recovers those
 * without lowering the similarity bar — which matters, because Valleyfair has
 * both a "Wild Thing" and a "Mild Thing" and they must never merge.
 */
export function nameVariants(input) {
  const base = normName(input);
  if (!base) return [];

  const out = new Set([base]);
  const add = (v) => {
    const n = v.replace(/\s+/g, " ").trim();
    if (n.length >= 3) out.add(n);
  };

  // Split on subtitle separators and keep both halves.
  for (const sep of [":", " - ", " \u2013 ", " \u2014 "]) {
    const raw = String(input);
    if (!raw.includes(sep)) continue;
    const [head, ...rest] = raw.split(sep);
    add(normName(head));
    add(normName(rest.join(sep)));
  }

  // Trailing ride-type words the two sources apply inconsistently.
  add(base.replace(/\s+(coaster|ride|the ride|experience)$/g, ""));

  // Non-English leading articles.
  add(base.replace(/^(le|la|les|el|los|las|der|die|das|het|de|il|lo|un|una)\s+/, ""));

  // Spacing and hyphenation differences: "PowderKeg" vs "Powder Keg".
  out.add(base.replace(/\s+/g, ""));

  return [...out].filter(Boolean);
}

/** Best similarity across every pair of normalised variants. */
export function bestSimilarity(a, b) {
  const A = nameVariants(a);
  const B = nameVariants(b);
  let best = 0;
  for (const x of A) {
    for (const y of B) {
      if (x === y) return 1;
      const s = similarity(x, y);
      if (s > best) best = s;
    }
  }
  return best;
}
