// themeparks.wiki — the identity spine for parks and attractions.
// MIT-licensed library behind a free API. Gives complete, maintained attraction
// lists for the ~200 destinations that generate most of the world's ride logging,
// including per-attraction coordinates, which saves us needing OSM geometry.

import { getJSON, mapLimit } from "../util/http.mjs";

const BASE = "https://api.themeparks.wiki/v1";
const RATE = 6; // requests/sec — generous but not rude

export const SOURCE = {
  key: "themeparks",
  name: "ThemeParks.wiki",
  url: "https://themeparks.wiki",
  licence: "Free API (MIT-licensed client library)",
};

export async function fetchThemeParks({ log = console.log } = {}) {
  const { destinations = [] } = await getJSON(`${BASE}/destinations`, {
    perSecond: RATE,
    label: "destinations",
  });

  const parkRefs = destinations.flatMap((d) =>
    (d.parks ?? []).map((p) => ({
      id: p.id,
      name: p.name,
      destinationId: d.id,
      destinationName: d.name,
      destinationSlug: d.slug ?? null,
    })),
  );

  log(`  ${destinations.length} destinations, ${parkRefs.length} parks`);

  // Park detail gives us coordinates and timezone.
  const details = await mapLimit(
    parkRefs,
    4,
    async (p) => {
      try {
        return await getJSON(`${BASE}/entity/${p.id}`, {
          perSecond: RATE,
          label: `park ${p.name}`,
        });
      } catch {
        return null;
      }
    },
    (done, total) => log(`  park detail ${done}/${total}`),
  );

  // Children give us the full attraction list per park.
  const childSets = await mapLimit(
    parkRefs,
    4,
    async (p) => {
      try {
        const res = await getJSON(`${BASE}/entity/${p.id}/children`, {
          perSecond: RATE,
          label: `children ${p.name}`,
        });
        return res.children ?? [];
      } catch {
        return [];
      }
    },
    (done, total) => log(`  attraction lists ${done}/${total}`),
  );

  const parks = parkRefs.map((p, i) => {
    const d = details[i];
    return {
      sourceId: p.id,
      name: p.name,
      destinationId: p.destinationId,
      destinationName: p.destinationName,
      destinationSlug: p.destinationSlug,
      latitude: d?.location?.latitude ?? null,
      longitude: d?.location?.longitude ?? null,
      timezone: d?.timezone ?? null,
      externalId: d?.externalId ?? null,
    };
  });

  const attractions = [];
  for (let i = 0; i < parkRefs.length; i++) {
    for (const c of childSets[i]) {
      // Restaurants and hotels are not attractions we log rides on.
      if (c.entityType !== "ATTRACTION" && c.entityType !== "SHOW") continue;
      attractions.push({
        sourceId: c.id,
        name: c.name,
        parkSourceId: parkRefs[i].id,
        parkName: parkRefs[i].name,
        entityType: c.entityType,
        externalId: c.externalId ?? null,
        latitude: c.location?.latitude ?? null,
        longitude: c.location?.longitude ?? null,
      });
    }
  }

  return { destinations, parks, attractions };
}
