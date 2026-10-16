// Place suggestions for an activity's location (#73), from Google's Places
// API (New) Autocomplete. Runs here so the Google key never reaches the
// browser, and only for signed-in users within their daily quota (enforced by
// consume_api_quota in the database).
import { autocomplete, clientFor, cors, json, useQuota } from "../_shared/common.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "Sign in to search places." }, 401);

  let input = "";
  let languageCode = "en";
  try {
    const body = await req.json();
    input = typeof body?.input === "string" ? body.input.trim() : "";
    if (typeof body?.languageCode === "string" && /^[A-Za-z-]{2,10}$/.test(body.languageCode)) {
      languageCode = body.languageCode;
    }
  } catch {
    return json({ error: "Send JSON with an input." }, 400);
  }
  // Too short to be useful, or not a place: answer without spending a search.
  if (input.length < 3 || input.length > 200) return json({ suggestions: [] });

  const key = Deno.env.get("GOOGLE_MAPS_API_KEY");
  if (!key) {
    console.error("GOOGLE_MAPS_API_KEY is not set");
    return json({ error: "Place search isn't set up yet." }, 503);
  }

  // Count the search against the caller's own quota, as the caller.
  const quota = await useQuota(clientFor(authorization), "places");
  if (quota === "limit") {
    return json({ error: "You've used today's place searches. Type the location yourself, or try again tomorrow." }, 429);
  }
  if (quota === "unauthorized") return json({ error: "Sign in to search places." }, 401);

  try {
    return json({ suggestions: await autocomplete(input, key, languageCode) });
  } catch (e) {
    console.error("places request failed", e);
    return json({ error: "Place search is unavailable right now." }, 502);
  }
});
