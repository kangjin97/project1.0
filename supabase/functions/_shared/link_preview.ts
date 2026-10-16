// What a pasted link says about itself, from official sources only (#74,
// owner's choice): TikTok and YouTube oEmbed, and a normal page's own preview
// tags (Open Graph, <title>, meta description). No video downloads and no
// crawling: one request for the page (or oEmbed), one for its preview image.
// Instagram and Facebook have no official preview without Meta's API, so
// they aren't fetched; the user adds a screenshot or the caption instead.

export type LinkSource = "tiktok" | "youtube" | "web" | "meta" | "none";

export type LinkPreview = {
  source: LinkSource;
  url: string;
  title?: string;
  description?: string;
  author?: string;
  siteName?: string;
  imageUrl?: string;
};

export type FetchedImage = { data: string; mediaType: "image/jpeg" | "image/png" | "image/gif" | "image/webp" };

const PAGE_LIMIT = 512 * 1024; // enough for any <head>
const IMAGE_LIMIT = 4 * 1024 * 1024; // keeps the Claude request small
const TIMEOUT_MS = 6000;
const USER_AGENT = "EasyPlanBot/1.0 (+https://easyplan-hehe.netlify.app; link previews)";

/** Which official source a link belongs to. */
export function classify(url: URL): LinkSource {
  const host = url.hostname.toLowerCase().replace(/^www\.|^m\./, "");
  if (host === "tiktok.com" || host.endsWith(".tiktok.com")) return "tiktok";
  if (host === "youtube.com" || host === "youtu.be" || host.endsWith(".youtube.com")) return "youtube";
  if (["instagram.com", "facebook.com", "fb.watch", "threads.net"].some((h) => host === h || host.endsWith(`.${h}`))) {
    return "meta";
  }
  return "web";
}

/**
 * The link as a URL we're willing to fetch: http(s) only, and never a
 * private, local or link-local address (so a pasted link can't make the
 * server probe its own network). Returns null otherwise.
 */
export function safeUrl(raw: string): URL | null {
  let url: URL;
  try {
    url = new URL(raw.trim().includes("://") ? raw.trim() : `https://${raw.trim()}`);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  if (url.username || url.password) return null;
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (!host.includes(".") && !host.includes(":")) return null; // "localhost", intranet names
  if (host.endsWith(".local") || host.endsWith(".internal") || host.endsWith(".localhost")) return null;
  const v4 = host.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (v4) {
    const [a, b] = [Number(v4[1]), Number(v4[2])];
    if (a === 0 || a === 10 || a === 127 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127) || a >= 224) return null;
  }
  if (host.includes(":")) {
    // IPv6 literal: refuse loopback, unique-local and link-local.
    if (host === "::1" || host === "::" || /^f[cd]/.test(host) || /^fe[89ab]/.test(host)) return null;
  }
  return url;
}

/** GET with a timeout, following at most 3 redirects, each one re-checked. */
async function safeFetch(start: URL, accept: string): Promise<Response | null> {
  let url = start;
  for (let hop = 0; hop < 4; hop++) {
    const res = await fetch(url, {
      redirect: "manual",
      headers: { "User-Agent": USER_AGENT, Accept: accept, "Accept-Language": "en" },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (res.status >= 300 && res.status < 400) {
      const next = res.headers.get("location");
      await res.body?.cancel();
      const checked = next ? safeUrl(new URL(next, url).toString()) : null;
      if (!checked) return null;
      url = checked;
      continue;
    }
    return res.ok ? res : null;
  }
  return null;
}

/** Reads at most [limit] bytes of a body. */
async function readLimited(res: Response, limit: number): Promise<Uint8Array> {
  const reader = res.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (size < limit) {
    const { done, value } = await reader.read();
    if (done || !value) break;
    chunks.push(value);
    size += value.length;
  }
  await reader.cancel().catch(() => {});
  const out = new Uint8Array(Math.min(size, limit));
  let at = 0;
  for (const c of chunks) {
    const part = c.subarray(0, Math.min(c.length, out.length - at));
    out.set(part, at);
    at += part.length;
    if (at >= out.length) break;
  }
  return out;
}

async function oembed(endpoint: string, url: URL, source: LinkSource): Promise<LinkPreview> {
  const res = await safeFetch(new URL(`${endpoint}?format=json&url=${encodeURIComponent(url.toString())}`), "application/json");
  if (!res) return { source, url: url.toString() };
  const data = JSON.parse(new TextDecoder().decode(await readLimited(res, PAGE_LIMIT)));
  return {
    source,
    url: url.toString(),
    title: str(data?.title),
    author: str(data?.author_name),
    siteName: str(data?.provider_name),
    imageUrl: str(data?.thumbnail_url),
  };
}

const str = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim().slice(0, 2000) : undefined);

const decodeEntities = (s: string) =>
  s.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|#39);/gi, (_, e: string) => {
    const lower = e.toLowerCase();
    if (lower.startsWith("#x")) return String.fromCodePoint(parseInt(lower.slice(2), 16));
    if (lower.startsWith("#")) return String.fromCodePoint(parseInt(lower.slice(1), 10));
    return { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" }[lower] ?? "'";
  });

/** A page's own preview tags. */
export function parsePreviewTags(html: string): Omit<LinkPreview, "source" | "url"> {
  const end = html.search(/<\/head>/i);
  const head = end > 0 ? html.slice(0, end) : html;
  const meta = (name: string) => {
    for (const tag of head.match(/<meta\b[^>]*>/gi) ?? []) {
      const key = tag.match(/\b(?:property|name)\s*=\s*["']([^"']+)["']/i)?.[1]?.toLowerCase();
      if (key !== name) continue;
      const content = tag.match(/\bcontent\s*=\s*"([^"]*)"|\bcontent\s*=\s*'([^']*)'/i);
      const value = content?.[1] ?? content?.[2];
      if (value?.trim()) return decodeEntities(value.trim()).slice(0, 2000);
    }
    return undefined;
  };
  const title = head.match(/<title[^>]*>([^<]*)<\/title>/i)?.[1];
  return {
    title: meta("og:title") ?? meta("twitter:title") ?? (title ? decodeEntities(title.trim()) : undefined),
    description: meta("og:description") ?? meta("twitter:description") ?? meta("description"),
    siteName: meta("og:site_name"),
    imageUrl: meta("og:image:secure_url") ?? meta("og:image") ?? meta("twitter:image"),
  };
}

/** What [raw] says about itself. Never throws; unreadable links come back with only a source. */
export async function readLink(raw: string): Promise<LinkPreview> {
  const url = safeUrl(raw);
  if (!url) return { source: "none", url: raw };
  const source = classify(url);
  try {
    if (source === "tiktok") return await oembed("https://www.tiktok.com/oembed", url, source);
    if (source === "youtube") return await oembed("https://www.youtube.com/oembed", url, source);
    if (source === "meta") return { source, url: url.toString() };
    const res = await safeFetch(url, "text/html,application/xhtml+xml");
    if (!res || !(res.headers.get("content-type") ?? "").includes("html")) return { source, url: url.toString() };
    const html = new TextDecoder().decode(await readLimited(res, PAGE_LIMIT));
    const tags = parsePreviewTags(html);
    if (tags.imageUrl) tags.imageUrl = new URL(tags.imageUrl, url).toString();
    return { source, url: url.toString(), ...tags };
  } catch (e) {
    console.error("reading link failed", source, e);
    return { source, url: url.toString() };
  }
}

/** The preview image, if it's a small enough image Claude can read. Never throws. */
export async function fetchImage(raw: string | undefined): Promise<FetchedImage | null> {
  const url = raw ? safeUrl(raw) : null;
  if (!url) return null;
  try {
    const res = await safeFetch(url, "image/*");
    const type = (res?.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase();
    if (!res || !["image/jpeg", "image/png", "image/gif", "image/webp"].includes(type)) {
      await res?.body?.cancel();
      return null;
    }
    const bytes = await readLimited(res, IMAGE_LIMIT + 1);
    if (bytes.length > IMAGE_LIMIT) return null;
    return { data: base64(bytes), mediaType: type as FetchedImage["mediaType"] };
  } catch (e) {
    console.error("fetching preview image failed", e);
    return null;
  }
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}
