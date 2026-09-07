# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Commands

Deno is the only runtime and `deno.json` the only manifest. There is no `package.json`: the npm packages (Vite, Tailwind, the Elm compiler) are `npm:` specifiers in `imports`, which is what makes `deno install` materialise `node_modules/` and `node_modules/.bin/`. Nothing in `src/` imports them — the import map is the dependency list. Never invoke Node, `npm` or `npx`.

```sh
deno install                      # resolve npm deps, materialise node_modules/
deno task build                   # vite build -> dist/ (must exist before `serve`)
deno task serve                   # :8000 — Deno API proxy + static dist/
deno task dev                     # :5173 — Vite dev server, proxies /api to :8000
deno task test                    # elm-test --workers 1
deno task format                  # elm-format src tests --yes
```

Local development needs both `deno task serve` and `deno task dev` running: the Deno server owns `/api`, Vite forwards to it, so dev and production URL shapes are identical.

Running a subset of tests — extra args pass through the task, and `elm-test` has no name filter, so file/glob is the finest granularity:

```sh
deno task test tests/DomainTest.elm
deno task test "tests/**/*Test.elm"
```

Compile-check without running: `./node_modules/.bin/elm-test make tests/DomainTest.elm`.

### Two toolchain workarounds — do not "clean up"

- `test` pins `--workers 1`. Multi-worker `elm-test` forks over a Unix named pipe that races under Deno (`connect ENOENT`, 4 failures in 10 runs). Node-only problem; revert if Deno fixes it.
- `format` calls `./node_modules/.bin/elm-format` by explicit path. `elm-format`'s `bin` entry is a native binary; resolved through the canonical `deno.json` path it gets handed to the JS runtime and dies with `SyntaxError`. POSIX-only, same assumption `server/main.ts` already makes.

## Architecture

Elm 0.19.2 `Browser.element` frontend, one Deno process serving `dist/` and proxying an allowlisted slice of Red Eléctrica's REData API.

```
src/Main.elm          Model/update/effects/controls — the only module that knows Slots
src/View/Figures.elm  The tables: one period alone, and two with the change between
src/View/Value.elm    Figures, gaps, units, table furniture — all Html msg
src/Api/Request.elm   URL construction + Http.Response -> Result Error
src/Api/Decode.elm    JSON -> Breakdown (needs the requested Period; see below)
src/Domain/*.elm      Pure types and arithmetic; no Http, no Html
server/main.ts        Static dist/ + /api proxy: allowlist, per-isolate cache, SPA fallback
tests/                DomainTest.elm, ApiTest.elm, Fixtures/{Captured,Synthetic}.elm
```

Domain layering (imports only flow downward): `Comparison` → `Breakdown` → {`Reading`, `Technology`, `Region`, `Period`}, with `Measure` over `Reading`. `RemoteData` stands alone.

View layering, same rule: `Main` → `View.Figures` → `View.Value` → `Domain/*`. **The split follows the types, not the layers.** Anything whose signature mentions `Model` or `Msg` stays in `Main`; anything that is `Html msg` — a projection of domain values that cannot originate an event — belongs in `View/`. Do not split `Main` into `Model.elm`/`Update.elm`/`View.elm`: Elm's module graph must be acyclic, so that shape forces `Msg` into a types module nothing owns while leaving every file dependent on the whole `Model`. If a `View/*` function needs to emit a message, take the constructor as an argument (`(Region -> msg) -> …`) rather than importing `Main`.

**One comparison = two independent requests.** REData caps date ranges (5 years for `time_trunc=year`, 24 months for `month`), so a single request spanning both periods can fail where two single-period requests always succeed. `Main` therefore keys everything by `Slot` (`A` | `B`) — `periodFor`/`setPeriod`/`breakdownFor`/`setBreakdown` are the accessors — and each slot holds its own `RemoteData Breakdown`, so one period failing leaves the other on screen.

**The decoder is handed the requested `Period`.** REData has no nulls: missing data is an *absent array entry*, so a gap only exists relative to the timeline you asked for. `Api.Decode.breakdown : Region -> Period -> Decoder Breakdown` constructs `Reading.Missing` itself rather than letting a ragged series through.

**Asymmetric slots by design.** `periodA : Period` (asked at `init`, starts `Loading`), `periodB : Maybe Period` (`NotAsked` until the user picks). `measure` is one field for the whole screen, not one per slot. `Model` deliberately holds loose fields instead of a `Comparison` record — see the long rationale at the top of [src/Main.elm](src/Main.elm).

## Invariants the code is built around

Each is argued at length in the module that owns it, and summarised in [README.md](README.md). Changing any of them means changing that argument, not just the code.

- **Absence is a variant, never `0` or a dash.** `Reading = Present Float | Missing`; `Reading.sum` returns `Complete | Partial | NoData`, never a bare `Float`, so a partial total cannot render as if it were whole. No absent figure renders as `—` in a numeric column.
- **Never trust the API's metadata about its own data.** `percentage` is exactly half the true share and absolute-valued (not decoded at all — share is `value / total`). `attributes.type` calls non-renewable waste `Renovable` in 15 of 19 regions, so `Technology.ourClassification` wins and the API field is only a fallback for `Unrecognised`. Indicator `id` is not stable across region id-families (offset by 42); decoding keys on `title`.
- **`Technology` has `Unrecognised String`; `Region` does not.** The technology vocabulary is open and unstable; Spanish administrative geography is closed and all 19 `geo_id`s are confirmed, so `Region.toGeoId` is total. A region/id mapping counts as confirmed only if a real response or REE's own published source states the name — never inferred from the shape of the data.
- **`Measure` is a type, not a `Bool`,** and `Quantity` (`Megawatthours | Percentage | PercentagePoints`) keeps numbers inseparable from their units. Adding a third measure must break `axisLabel`, `changeColumnLabel`, row ordering and `changeIn` at compile time.
- **No unreachable variants.** `Period.Granularity` has two constructors because only `month` and `year` work at `geo_limit=ccaa`; `Reading` has no `Provisional`. The codebase repeatedly refuses to add a state nothing can reach — match that instinct rather than modelling for symmetry.
- **Error bodies may not be JSON.** `Api.Request.interpretResponse` binds the error body to `_` and never parses it; a decode failure means exactly one thing — a 2xx whose body did not match.

## Proxy rules (`server/main.ts`)

The proxy is not for CORS (upstream sends `access-control-allow-origin: *`); it exists for latency, for not shipping an open relay, and because upstream `OPTIONS` preflight returns 403. When touching it:

- Language, category, widget and every query parameter are validated against literal allowlists; unknown parameters are **rejected**, not ignored. The upstream query string is rebuilt from scratch in sorted order so the cache key is canonical.
- No client headers are forwarded upstream.
- Only successful responses are cached (an upstream 502 is a stable property of a bad id, and caching failures would make an outage sticky). The `Map` cache is best-effort per isolate.
- Errors pass through with their real status and content type — never flattened to 500 or forced to JSON.
- The SPA fallback serves `index.html` only when the request accepts HTML, so a missing `.js`/`.css` stays a 404.
- Adding any custom request header to the Elm client would break every request against upstream's 403 preflight if the proxy were ever bypassed.

## Conventions

- **Doc comments carry the argument, not the description.** Modules and non-obvious functions explain *why* the design is what it is, including alternatives rejected and the condition under which the decision would flip. New code in this style is expected; a change that invalidates an existing rationale should update that prose in the same commit.
- **Fixtures are segregated by provenance.** `tests/Fixtures/Captured.elm` is verbatim live-API output (evidence); `tests/Fixtures/Synthetic.elm` is hand-written (construction). Never mix them in one module — a reader must not have to check which kind a fixture is.
- Run `deno task format` before committing; the repo is uniformly `elm-format`ed.
- Tailwind v4 via `@tailwindcss/vite`; the only CSS file is [src/styles.css](src/styles.css), which just imports Tailwind and points `@source` at the Elm sources. Styling lives in `class` attributes across [src/Main.elm](src/Main.elm) and [src/View/](src/View/); `@source` globs `src/**/*.elm`, so a new module under `src/` is picked up with no config change.
- Commit subjects follow `type(scope): summary` — e.g. `feat(app):`, `test(domain):`, `doc:`.
