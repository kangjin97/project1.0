// Place suggestions for an activity's location (#73), from Google's Places
// API (New) Autocomplete. Runs here so the Google key never reaches the
// browser, and only for signed-in users within their daily quota (enforced by
// consume_api_quota in the database).
//
// Billing: plain per-request Autocomplete, no sessions or Place Details. A
// location usually takes a few searches and the suggestion already carries
// the place ID and its text, so a terminating Place Details call would only
// add cost. See docs/ai/decisions.md.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

// What the app gets: enough to show a suggestion and keep the pick.
type Suggestion = { placeId: string; text: string; mainText: string; secondaryText: string };

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
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );
  const { error: quotaError } = await supabase.rpc("consume_api_quota", { p_kind: "places" });
  if (quotaError) {
    if (quotaError.code === "PT429") {
      return json({ error: "You've used today's place searches. Type the location yourself, or try again tomorrow." }, 429);
    }
    console.error("quota check failed", quotaError.code, quotaError.message);
    return json({ error: "Sign in to search places." }, 401);
  }

  let response: Response;
  try {
    response = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": key,
        "X-Goog-FieldMask":
          "suggestions.placePrediction.placeId,suggestions.placePrediction.text.text," +
          "suggestions.placePrediction.structuredFormat",
      },
      body: JSON.stringify({ input, languageCode }),
      signal: AbortSignal.timeout(5000),
    });
  } catch (e) {
    console.error("places request failed", e);
    return json({ error: "Place search is unavailable right now." }, 502);
  }
  if (!response.ok) {
    console.error("places responded", response.status, (await response.text()).slice(0, 500));
    return json({ error: "Place search is unavailable right now." }, 502);
  }

  const data = await response.json();
  const suggestions: Suggestion[] = [];
  for (const s of data?.suggestions ?? []) {
    const p = s?.placePrediction;
    if (!p?.placeId) continue;
    const text: string = p.text?.text ?? "";
    suggestions.push({
      placeId: p.placeId,
      text,
      mainText: p.structuredFormat?.mainText?.text ?? text,
      secondaryText: p.structuredFormat?.secondaryText?.text ?? "",
    });
  }
  return json({ suggestions });
});
