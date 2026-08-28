// Polite HTTP with an on-disk cache. Every source here is a free service run by
// volunteers, so we cache aggressively and rate-limit rather than hammering them.

import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const CACHE_DIR = join(ROOT, ".cache");

export const USER_AGENT =
  "CoasterHunter/0.1 (seed pipeline; contact: william@biigplanet.com)";

let useCache = true;
export function setCacheEnabled(v) {
  useCache = v;
}

// One token bucket per host so a slow source can't starve the others.
const buckets = new Map();
function bucketFor(host, perSecond) {
  if (!buckets.has(host)) buckets.set(host, { next: 0, gap: 1000 / perSecond });
  return buckets.get(host);
}

async function throttle(host, perSecond) {
  const b = bucketFor(host, perSecond);
  const now = Date.now();
  const at = Math.max(now, b.next);
  b.next = at + b.gap;
  if (at > now) await new Promise((r) => setTimeout(r, at - now));
}

function cachePath(url, body) {
  const key = createHash("sha1").update(url + (body ?? "")).digest("hex");
  return join(CACHE_DIR, key.slice(0, 2), `${key}.json`);
}

/**
 * Fetch JSON with caching, throttling and retry.
 * @param {string} url
 * @param {{ body?: string, headers?: Record<string,string>, perSecond?: number,
 *           retries?: number, label?: string }} [opts]
 */
export async function getJSON(url, opts = {}) {
  const { body, headers = {}, perSecond = 5, retries = 3, label } = opts;
  const file = cachePath(url, body);

  if (useCache) {
    try {
      return JSON.parse(await readFile(file, "utf8"));
    } catch {
      /* cache miss — fall through */
    }
  }

  const host = new URL(url).host;
  let lastErr;

  for (let attempt = 0; attempt <= retries; attempt++) {
    await throttle(host, perSecond);
    try {
      const res = await fetch(url, {
        method: body ? "POST" : "GET",
        headers: {
          "User-Agent": USER_AGENT,
          Accept: "application/json",
          ...(body ? { "Content-Type": "application/x-www-form-urlencoded" } : {}),
          ...headers,
        },
        body,
      });

      if (res.status === 429 || res.status >= 500) {
        throw new Error(`HTTP ${res.status}`);
      }
      if (!res.ok) {
        // 4xx other than rate limiting won't get better by retrying.
        const err = new Error(`HTTP ${res.status} for ${label ?? url}`);
        err.permanent = true;
        throw err;
      }

      const json = await res.json();
      await mkdir(dirname(file), { recursive: true });
      await writeFile(file, JSON.stringify(json));
      return json;
    } catch (err) {
      lastErr = err;
      if (err.permanent) break;
      const backoff = 500 * 2 ** attempt;
      if (attempt < retries) await new Promise((r) => setTimeout(r, backoff));
    }
  }
  throw new Error(`fetch failed: ${label ?? url} — ${lastErr?.message}`);
}

/** Run tasks with bounded concurrency, reporting progress. */
export async function mapLimit(items, limit, fn, onProgress) {
  const out = new Array(items.length);
  let index = 0;
  let done = 0;

  async function worker() {
    while (index < items.length) {
      const i = index++;
      out[i] = await fn(items[i], i);
      done++;
      if (onProgress && done % 10 === 0) onProgress(done, items.length);
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, worker),
  );
  if (onProgress) onProgress(items.length, items.length);
  return out;
}
