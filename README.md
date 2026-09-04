# renewable-analyzer

Compare renewable generation across Spanish regions and time periods, using
Red Eléctrica's public [REData API](https://www.ree.es/es/datos/apidatos).

> **Status: skeleton.** Toolchain, server and proxy are working and verified.
> There is no domain model and no UI yet.

## Stack

| Piece | Choice |
|---|---|
| Frontend | Elm 0.19.2, `Browser.element` *(provisional)* |
| Build | Vite 8 + `vite-plugin-elm` |
| Styling | Tailwind CSS v4 via `@tailwindcss/vite` |
| Server & proxy | Deno, `Deno.serve()` + `@std/http/file-server` |
| Hosting | Deno Deploy — single origin for app and proxy |

## Local development

Two processes. The Deno server owns `/api`; Vite serves the app and forwards
`/api` to it, so dev and production URL shapes are identical.

```sh
npm install
npm run build      # dist/ must exist for the Deno server to serve anything
deno task serve    # :8000 — API proxy + static dist/
npm run dev        # :5173 — Vite dev server, proxies /api to :8000
```

Other tasks: `npm test` (elm-test), `npm run format` (elm-format).

## The proxy

`server/main.ts` serves `dist/` and proxies an **allowlisted** subset of REData.
It is not a general-purpose relay: language, category, widget and every query
parameter are validated against literal allowlists, unknown parameters are
rejected outright, and the upstream query string is rebuilt from scratch rather
than forwarded.

Note that the proxy is **not** needed for CORS — upstream sends
`access-control-allow-origin: *`. It exists for three other reasons:
latency (upstream cache misses take 2–5 s, and 15–23 s under concurrency), 
not shipping an open relay, and insulating the app from upstream's `OPTIONS` 
preflight returning 403.

## Licence

MIT — see [LICENSE](LICENSE).
