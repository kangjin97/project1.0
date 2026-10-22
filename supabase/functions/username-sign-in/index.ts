// Sign in with a username (#107). Supabase Auth signs in by email, so this
// looks the email up with the service role and signs in on the person's
// behalf. The email never reaches the app, as the privacy policy promises:
// the reply is only the new session's refresh token.
//
// Wrong usernames and wrong passwords get the same answer, and both count
// towards a per-username limit in the database (email_for_username), since
// every attempt reaches Auth from this function's one address.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { cors, json } from "../_shared/common.ts";

const USERNAME = /^[a-z0-9_]{3,30}$/;
const wrong = () => json({ error: "Wrong username, email or password.", code: "invalid_credentials" }, 400);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  let username = "", password = "";
  try {
    const body = await req.json();
    username = typeof body?.username === "string" ? body.username.trim().toLowerCase() : "";
    password = typeof body?.password === "string" ? body.password : "";
  } catch {
    return json({ error: "Send JSON with a username and password." }, 400);
  }
  if (!USERNAME.test(username) || password.length === 0 || password.length > 200) return wrong();

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const { data: email, error: lookupError } = await admin.rpc("email_for_username", { p_username: username });
  if (lookupError) {
    if (lookupError.code === "PT429") {
      return json({ error: "Too many tries. Wait 15 minutes, or sign in with your email.", code: "too_many_tries" }, 429);
    }
    console.error("username lookup failed", lookupError.code, lookupError.message);
    return json({ error: "Signing in is unavailable right now. Try your email." }, 502);
  }
  if (!email) {
    await admin.rpc("record_username_sign_in_failure", { p_username: username });
    return wrong();
  }

  const auth = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: Deno.env.get("SUPABASE_ANON_KEY")! },
    body: JSON.stringify({ email, password }),
  });
  const reply = await auth.json().catch(() => ({}));
  if (auth.ok && reply?.refresh_token) {
    await admin.rpc("clear_username_sign_in_failures", { p_username: username });
    return json({ refresh_token: reply.refresh_token });
  }

  const code = reply?.error_code ?? reply?.code;
  if (code === "email_not_confirmed") {
    return json({ error: "Confirm your email first: open the link we sent when you signed up.", code }, 400);
  }
  if (auth.status === 429) {
    return json({ error: "Too many sign-ins right now. Wait a minute, or sign in with your email.", code: "rate_limited" }, 429);
  }
  if (code === "invalid_credentials" || auth.status === 400) {
    await admin.rpc("record_username_sign_in_failure", { p_username: username });
    return wrong();
  }
  console.error("auth sign-in failed", auth.status, code);
  return json({ error: "Signing in is unavailable right now. Try your email." }, 502);
});
