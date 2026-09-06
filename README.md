# renewable-analyzer

Compare renewable generation across Spanish regions and time periods, using
Red Eléctrica's public [REData API](https://www.ree.es/es/datos/apidatos).

## Stack

| Piece | Choice |
|---|---|
| Frontend | Elm 0.19.2, `Browser.element` |
| Build | Vite 8 + `vite-plugin-elm` |
| Styling | Tailwind CSS v4 via `@tailwindcss/vite` |
| Server & proxy | Deno, `Deno.serve()` + `@std/http/file-server` |
| Tooling | Deno only — task runner, npm resolution, lockfile, typecheck |
| Hosting | Deno Deploy — single origin for app and proxy |

## Local development

Two processes. The Deno server owns `/api`; Vite serves the app and forwards
`/api` to it, so dev and production URL shapes are identical.

```sh
deno install       # resolves npm dependencies and materialises node_modules/
deno task build    # dist/ must exist for the Deno server to serve anything
deno task serve    # :8000 — API proxy + static dist/
deno task dev      # :5173 — Vite dev server, proxies /api to :8000
```

Other tasks: `deno task test` (elm-test), `deno task format` (elm-format).
Both carry a Deno-specific workaround — see [Toolchain notes](#toolchain-notes).

**Deno is the only runtime — Node is never invoked.** `package.json` remains solely
as the npm dependency manifest: Vite, Tailwind and the Elm compiler are npm
packages, and it also carries the `"type": "module"` that Vite needs to read
`vite.config.js` as ESM. The lockfile is `deno.lock`, which pins all 146 npm
packages including the platform-specific compiler binaries, so `package-lock.json`
was removed as redundant.

## Toolchain notes

Two tasks work around Deno's Node-compatibility layer. Both are one line in
`deno.json`, and both should be reverted if Deno fixes the underlying behaviour.

**`deno task test` runs `elm-test --workers 1`.** With more than one worker,
`elm-test` opens a Unix named pipe at `/tmp/elm_test-<pid>.sock` and forks workers
that connect back to it. Under Deno that handshake races, and a worker dies with
`connect ENOENT`: 4 failures in 10 runs, against 0 in 15 once pinned. This removes
the mechanism rather than retrying around it — `Supervisor.js` skips the pipe
entirely when there is a single worker — and at this suite size it is also faster
(39 ms against ~310 ms), since nothing pays for the fork and IPC setup. Worth
revisiting only when the suite is large enough for parallelism to earn its cost;
the race is Deno-specific and multi-worker is fine under Node.

**`deno task format` calls `./node_modules/.bin/elm-format` by path.** The
`elm-format` package points its `bin` entry at a native executable — its install
script overwrites the JS shim with the platform binary. Resolved through Deno's
canonical `deno.json` path, that file is handed to the JavaScript runtime and dies
with `SyntaxError: Invalid or unexpected token`. The trigger is the config path
rather than the command: a byte-identical config under any other filename runs the
same command line successfully, and `npx elm-format` fails identically. The
explicit path bypasses the resolver and executes the binary directly. That form is
POSIX-only — npm writes a `.cmd` shim on Windows — which is the same assumption
`server/main.ts` already makes.

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
