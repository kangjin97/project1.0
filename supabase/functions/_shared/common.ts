// Shared by the Edge Functions: CORS, JSON replies, the per-user quota and
// Google place search. Folders starting with "_" aren't deployed as functions.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.117.2";

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

/** A Supabase client acting as the caller, so RLS and auth.uid() apply. */
export const clientFor = (authorization: string): SupabaseClient =>
  createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
  });

export type QuotaResult = "ok" | "limit" | "unauthorized";

/** Counts one call of [kind] for the caller (consume_api_quota in the database). */
export async function useQuota(supabase: SupabaseClient, kind: string): Promise<QuotaResult> {
  const { error } = await supabase.rpc("consume_api_quota", { p_kind: kind });
  if (!error) return "ok";
  if (error.code === "PT429") return "limit";
  console.error("quota check failed", kind, error.code, error.message);
  return "unauthorized";
}

/** What the app gets for a place: enough to show it and keep the pick. */
export type PlaceSuggestion = { placeId: string; text: string; mainText: string; secondaryText: string };

/**
 * Google Places API (New) Autocomplete for [input]. Billed per request (no
 * session token, no Place Details): see docs/ai/decisions.md. Throws when
 * Google can't answer.
 */
export async function autocomplete(input: string, key: string, languageCode = "en"): Promise<PlaceSuggestion[]> {
  const response = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
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
  if (!response.ok) {
    throw new Error(`places responded ${response.status}: ${(await response.text()).slice(0, 500)}`);
  }
  const data = await response.json();
  const suggestions: PlaceSuggestion[] = [];
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
  return suggestions;
}
