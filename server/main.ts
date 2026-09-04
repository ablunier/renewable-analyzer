import { serveDir } from "@std/http/file-server";

const DIST_ROOT = new URL("../dist", import.meta.url).pathname;
const UPSTREAM = "https://apidatos.ree.es";
const CACHE_TTL_MS = 15 * 60 * 1000;

const ALLOWED_LANGS = new Set(["es", "en"]);
const ALLOWED_CATEGORIES = new Set(["generacion"]);
const ALLOWED_WIDGETS = new Set(["estructura-generacion"]);
const ALLOWED_TIME_TRUNC = new Set(["month", "year"]);
const ALLOWED_GEO_TRUNC = new Set(["electric_system"]);
const ALLOWED_GEO_LIMIT = new Set([
  "ccaa",
  "peninsular",
  "canarias",
  "baleares",
  "ceuta",
  "melilla",
]);

const DATE_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/;
const GEO_IDS_RE = /^\d{1,6}$/;

const PARAM_VALIDATORS: Record<string, (v: string) => boolean> = {
  start_date: (v) => DATE_RE.test(v),
  end_date: (v) => DATE_RE.test(v),
  time_trunc: (v) => ALLOWED_TIME_TRUNC.has(v),
  geo_trunc: (v) => ALLOWED_GEO_TRUNC.has(v),
  geo_limit: (v) => ALLOWED_GEO_LIMIT.has(v),
  geo_ids: (v) => GEO_IDS_RE.test(v),
};

type CacheEntry = {
  status: number;
  body: string;
  contentType: string;
  expiresAt: number;
};

const cache = new Map<string, CacheEntry>();

function jsonError(status: number, detail: string): Response {
  return new Response(
    JSON.stringify({ errors: [{ status: String(status), detail }] }),
    {
      status,
      headers: { "content-type": "application/json; charset=utf-8" },
    },
  );
}

function resolveUpstream(
  url: URL,
): { ok: true; target: string } | { ok: false; response: Response } {
  const segments = url.pathname.replace(/^\/api\/?/, "").split("/").filter(
    Boolean,
  );

  if (segments.length !== 4) {
    return {
      ok: false,
      response: jsonError(
        400,
        "Expected /api/{lang}/datos/{category}/{widget}",
      ),
    };
  }

  const [lang, datos, category, widget] = segments;
  if (!ALLOWED_LANGS.has(lang)) {
    return { ok: false, response: jsonError(400, `Disallowed lang: ${lang}`) };
  }
  if (datos !== "datos") {
    return {
      ok: false,
      response: jsonError(400, "Expected literal segment 'datos'"),
    };
  }
  if (!ALLOWED_CATEGORIES.has(category)) {
    return {
      ok: false,
      response: jsonError(400, `Disallowed category: ${category}`),
    };
  }
  if (!ALLOWED_WIDGETS.has(widget)) {
    return {
      ok: false,
      response: jsonError(400, `Disallowed widget: ${widget}`),
    };
  }

  const forwarded = new URLSearchParams();
  for (const name of Object.keys(PARAM_VALIDATORS).sort()) {
    const value = url.searchParams.get(name);
    if (value === null) continue;
    if (!PARAM_VALIDATORS[name](value)) {
      return {
        ok: false,
        response: jsonError(400, `Invalid value for ${name}: ${value}`),
      };
    }
    forwarded.set(name, value);
  }

  for (const name of url.searchParams.keys()) {
    if (!(name in PARAM_VALIDATORS)) {
      return {
        ok: false,
        response: jsonError(400, `Unknown query parameter: ${name}`),
      };
    }
  }

  return {
    ok: true,
    target: `${UPSTREAM}/${lang}/datos/${category}/${widget}?${forwarded}`,
  };
}

async function handleApi(url: URL): Promise<Response> {
  const resolved = resolveUpstream(url);
  if (!resolved.ok) return resolved.response;

  const key = resolved.target;
  const hit = cache.get(key);
  if (hit && hit.expiresAt > Date.now()) {
    return new Response(hit.body, {
      status: hit.status,
      headers: { "content-type": hit.contentType, "x-proxy-cache": "HIT" },
    });
  }

  let upstream: Response;
  try {
    upstream = await fetch(key, { headers: { accept: "application/json" } });
  } catch (cause) {
    return jsonError(
      502,
      `Could not reach upstream: ${
        cause instanceof Error ? cause.message : cause
      }`,
    );
  }

  const body = await upstream.text();
  const contentType = upstream.headers.get("content-type") ??
    "application/octet-stream";

  if (upstream.ok) {
    cache.set(key, {
      status: upstream.status,
      body,
      contentType,
      expiresAt: Date.now() + CACHE_TTL_MS,
    });
  }

  return new Response(body, {
    status: upstream.status,
    headers: { "content-type": contentType, "x-proxy-cache": "MISS" },
  });
}

Deno.serve(async (request: Request) => {
  const url = new URL(request.url);

  if (url.pathname.startsWith("/api")) {
    if (request.method !== "GET") {
      return jsonError(405, "Only GET is supported");
    }
    return await handleApi(url);
  }

  const response = await serveDir(request, { fsRoot: DIST_ROOT, quiet: true });

  if (
    response.status === 404 &&
    request.headers.get("accept")?.includes("text/html")
  ) {
    return await serveDir(new Request(new URL("/index.html", url), request), {
      fsRoot: DIST_ROOT,
      quiet: true,
    });
  }

  return response;
});
