// Everything is stored metric. Sources mix feet, miles per hour, inches and
// centimetres, sometimes within one record.

const FT_TO_M = 0.3048;
const MPH_TO_KMH = 1.609344;
const IN_TO_CM = 2.54;

/** Pull the first number out of messy wikitext like "310&nbsp;ft (94 m)". */
export function firstNumber(value) {
  if (value == null) return null;
  const m = String(value).replace(/,/g, "").match(/-?\d+(?:\.\d+)?/);
  return m ? Number(m[0]) : null;
}

export const feetToMetres = (ft) => (ft == null ? null : round(ft * FT_TO_M, 1));
export const mphToKmh = (mph) => (mph == null ? null : round(mph * MPH_TO_KMH, 1));
export const inchesToCm = (inch) => (inch == null ? null : Math.round(inch * IN_TO_CM));

export function round(n, dp = 1) {
  if (n == null || Number.isNaN(n)) return null;
  const f = 10 ** dp;
  return Math.round(n * f) / f;
}

/**
 * Resolve a measurement that may appear in either unit system.
 * Prefers the metric field when both are present and they agree.
 */
export function preferMetric(metricRaw, imperialRaw, convert) {
  const metric = firstNumber(metricRaw);
  if (metric != null) return round(metric, 1);
  const imperial = firstNumber(imperialRaw);
  return imperial == null ? null : convert(imperial);
}

/** "1:30", "1 minute 30 seconds", "90" → seconds. */
export function durationToSeconds(value) {
  if (!value) return null;
  const s = String(value).toLowerCase();

  const clock = s.match(/(\d+)\s*:\s*(\d{1,2})/);
  if (clock) return Number(clock[1]) * 60 + Number(clock[2]);

  let total = 0;
  let matched = false;
  const min = s.match(/(\d+(?:\.\d+)?)\s*(?:minutes?|mins?|m\b)/);
  if (min) {
    total += Number(min[1]) * 60;
    matched = true;
  }
  const sec = s.match(/(\d+(?:\.\d+)?)\s*(?:seconds?|secs?|s\b)/);
  if (sec) {
    total += Number(sec[1]);
    matched = true;
  }
  if (matched) return Math.round(total);

  const bare = firstNumber(s);
  return bare == null ? null : Math.round(bare);
}
