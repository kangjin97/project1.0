// Where Google places are, for the distance filter (#94). Takes place IDs and
// answers their coordinates: from the cache when it has them (less than 30
// days old, Google's limit for keeping coordinates), otherwise from Google's
// Place Details, counted against the caller's daily quota and cached.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { clientFor, cors, json, useQuota } from "../_shared/common.ts";

const MAX_IDS = 50;
const PLACE_ID = /^[A-Za-z0-9_-]{10,300}$/;
const CACHE_DAYS = 30;

type Coordinates = { lat: number; lng: number };

/** Google Places API (New) Place Details, asking only for the location (Essentials). */
async function lookUp(placeId: string, key: string): Promise<Coordinates | null> {
  const response = await fetch(`https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`, {
    headers: { "X-Goog-Api-Key": key, "X-Goog-FieldMask": "location" },
    signal: AbortSignal.timeout(5000),
  });
  if (response.status === 404 || response.status === 400) return null; // gone or not a place
  if (!response.ok) throw new Error(`place details responded ${response.status}: ${(await response.text()).slice(0, 300)}`);
  const loc = (await response.json())?.location;
  const lat = Number(loc?.latitude), lng = Number(loc?.longitude);
  return Number.isFinite(lat) && Number.isFinite(lng) ? { lat, lng } : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "Sign in to see distances." }, 401);

  let ids: string[];
  try {
    const body = await req.json();
    ids = Array.isArray(body?.placeIds) ? body.placeIds : [];
  } catch {
    return json({ error: "Send JSON with placeIds." }, 400);
  }
  ids = [...new Set(ids.filter((id): id is string => typeof id === "string" && PLACE_ID.test(id)))];
  if (ids.length > MAX_IDS) return json({ error: `At most ${MAX_IDS} places at a time.` }, 400);
  if (ids.length === 0) return json({ coordinates: {} });

  // The cache has no client access; only this function (service role) uses it.
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const since = new Date(Date.now() - CACHE_DAYS * 24 * 3600 * 1000).toISOString();
  const { data: cached, error: cacheError } = await admin
    .from("place_coordinates").select("place_id, lat, lng").in("place_id", ids).gt("fetched_at", since);
  if (cacheError) {
    console.error("cache read failed", cacheError.message);
    return json({ error: "Distances are unavailable right now." }, 502);
  }
  const coordinates: Record<string, Coordinates> = {};
  for (const row of cached ?? []) coordinates[row.place_id] = { lat: row.lat, lng: row.lng };

  const missing = ids.filter((id) => !coordinates[id]);
  if (missing.length === 0) return json({ coordinates });

  const key = Deno.env.get("GOOGLE_MAPS_API_KEY");
  if (!key) {
    console.error("GOOGLE_MAPS_API_KEY is not set");
    return json({ coordinates, error: "Distances aren't set up yet." });
  }

  // Each Google lookup counts against the caller's quota, as the caller.
  const supabase = clientFor(authorization);
  let limitReached = false;
  for (const id of missing) {
    const quota = await useQuota(supabase, "place_coords");
    if (quota === "unauthorized") return json({ error: "Sign in to see distances." }, 401);
    if (quota === "limit") {
      limitReached = true;
      break;
    }
    try {
      const found = await lookUp(id, key);
      if (!found) continue;
      coordinates[id] = found;
      const { error } = await admin.from("place_coordinates")
        .upsert({ place_id: id, ...found, fetched_at: new Date().toISOString() });
      if (error) console.error("cache write failed", id, error.message);
    } catch (e) {
      console.error("place lookup failed", id, e);
    }
  }

  return json(limitReached
    ? { coordinates, error: "You've used today's distance lookups. Some places can't be measured until tomorrow." }
    : { coordinates });
});
