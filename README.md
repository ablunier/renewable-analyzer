# Renewable Analyzer Dashboard

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

## Design decisions

Four choices the rest of the code is built around. Each is argued at length in the module
it lives in; this is the short version.

### `Missing` is a variant, never `0`

A region that generated no wind and a region where wind was not measured are different
facts, and only one of them belongs in a sum. The API does not force the confusion, it
invites it: there are no nulls anywhere in any response, so a gap is an *absent array
entry* and only exists relative to the timeline you asked for — which is why the decoder
is handed the requested `Period` and constructs `Missing` itself rather than letting a
ragged series through. The rule then has to survive aggregation, so `Reading.sum` returns
`Complete | Partial | NoData` rather than a `Float`: adding up the present readings and
returning a number understates the total silently, where `Partial` forces the view to say
"12,345 MWh (2 of 9 technologies not measured)". No absent figure renders as a dash
either, because a dash in a column of numbers is read as a zero.

### Technologies are sorted by the size of the change

Alphabetical order makes the reader scan for what moved, and ordering by size makes them
scan past the big-but-static technologies; ordering by the magnitude of the difference
puts the technology that *explains* the change at the top, which is the question the
screen exists to answer. Technologies whose change is unknown sort last rather than
first — an absence of evidence is not evidence of a large movement. The rows re-sort when
the measure toggle is clicked, because MWh and percentage points disagree about the
biggest mover routinely: a technology can add 400 GWh and still lose share when total
generation grew faster. That costs stable rows and buys an ordering that stays true in
both modes, rather than one that quietly stops meaning what the caption says it means.

### `Technology` has an `Unrecognised String` variant, and `Region` does not

The API's technology vocabulary is open and observably unstable — 9 indicators per
autonomous community against 16 nationally, `Carbón` present 2014–2016 and gone from 2017,
`Fuel + Gas` and `Hidroeólica` in only two or three of the 19 regions — so a decoder that
dropped an unknown name would silently understate a region's generation. Spanish
administrative geography is closed and all 19 ids are confirmed, so `Region` needs no such
variant and `toGeoId` is total: the difference between the two types is a claim about
which vocabulary we actually control. An unrecognised technology renders under REData's
own name rather than as "Unknown", and is the single case where the API's
`Renovable`/`No-Renovable` field is believed — everywhere else our own classification
wins, because that field labels non-renewable waste as renewable in 15 of 19 regions.

### `Measure` is a type, not a boolean

Every `Bool` in a program has the same type, so nothing stops one being passed to the
wrong parameter or read the wrong way round, and `display True total reading` says nothing
at the call site about which way round `True` is. The measure decides four things — the
axis label, the change column's heading, the row ordering, and which arithmetic
`changeIn` performs — and each is a total function over `Energy | Share`, so a third
measure breaks all four at compile time where an `if`/`else` has no third branch to break.
`Measure` is a *view* concern rather than a property of the data: one request returns MWh
and share is derived from it, so the unit guarantee lives in `Quantity`
(`Megawatthours | Percentage | PercentagePoints`) instead — a number that cannot be
separated from its unit, and a percentage-point difference that cannot be printed under a
"%" label.

## Notes on the REData API

Everything below was verified against live responses in September 2026, and every claim
is reproducible with `curl`. It is here because most of it contradicts either REE's
documentation or the obvious assumption, and because three of the findings changed the
domain model rather than just the request layer.

### The `geo_ids` are undocumented

REE's documentation names the 19 autonomous communities and cities but publishes only
two example ids. The ids cannot be recovered from the API itself: `data.attributes.title`
is the **widget** name (`"Generación por tecnología"`) and is byte-identical for every
region, and a full-body grep of a `geo_ids=7` response for `castilla|mancha|galicia|geo|ccaa|region`
returns zero matches. The region's name, code and id appear **nowhere** in the response.
Walking the id range establishes which ids are *valid* — an unknown one returns 502 — but
it cannot label them.

The table is published, just not as a table. REE's own apidatos documentation page carries
an interactive two-box widget: the names are the `<option>` labels of `<select id="regionSelector">`,
and the ids live in `https://www.ree.es/themes/custom/ree/js/ree.js`, in the `switch` inside
`actualizarValoresGeo()`, where **each `case` carries the region name as a source comment**.
Name and id are therefore paired in REE's source, not by our own positional matching. The
English documentation page carries an identical list, which is independent corroboration
that it is maintained content rather than a stray artifact.

All 19 were then re-checked against a live request and return 200. They are hardcoded in
[`src/Domain/Region.elm`](src/Domain/Region.elm).

<details>
<summary>The confirmed table — 19 regions, <code>geo_limit=ccaa</code></summary>

| Region (as REE names it) | `geo_id` | Region (as REE names it) | `geo_id` |
|---|---|---|---|
| Andalucía | `4` | Comunidad Valenciana | `15` |
| Aragón | `5` | Extremadura | `16` |
| Cantabria | `6` | Galicia | `17` |
| Castilla la Mancha | `7` | La Rioja | `20` |
| Castilla y León | `8` | Región de Murcia | `21` |
| Cataluña | `9` | Islas Canarias | `8742` |
| País Vasco | `10` | Islas Baleares | `8743` |
| Principado de Asturias | `11` | Comunidad de Ceuta | `8744` |
| Comunidad de Madrid | `13` | Comunidad de Melilla | `8745` |
| Comunidad de Navarra | `14` | | |

REE's table says *Comunidad de Navarra* on both its Spanish and English pages; the
constitutionally correct *Comunidad Foral de Navarra* is a display choice for the UI to
make deliberately, not a data correction to smuggle into the table.

Ids `12`, `18` and `19` are valid and return real data, but no official source names
them, so they are not used. Id `12` returns data byte-identical to `8744` across 76
monthly datapoints, which is an equality test rather than an inference — but `8744` is
the id the published table prescribes, so nothing depends on accepting it. Ids `18` and
`19` are merely *near* `8743` and `8742` (totals differing by 0.0137% and 0.0007%) and
are deliberately **not** adopted: near is not identical, and their position in the numeric
sequence lining up with the two names the table skips is exactly the positional inference
this exercise refuses to make.

</details>

**The honesty rule this followed:** a mapping counts as confirmed only if a real response
or an official published table states the name. The shortcut available here was tempting
and wrong — since a valid id returns real generation data, you can guess which region an
id denotes from the shape of that data, because Galicia is windy and Ceuta generates
almost nothing. That is guessing, and a dashboard that silently mislabels a region is a
worse failure than one that admits it does not know.

Two structural surprises came out of the published table. The four island and city
communities reuse the **electric-system** ids `8742`–`8745` while still requiring
`geo_limit=ccaa`, so REE does not keep its two geographic axes disjoint and the id alone
is not a discriminator. And `geo_limit` does not select the geography at all — `geo_ids=8742`
returns an identical body under `geo_limit=ccaa` and under `geo_limit=canarias`. It only
gates which ids are legal.

### Three places the API's metadata about its own data is wrong

This is the finding that shaped the domain model. It happened three times, independently,
so the working assumption became: decode what the API measures, never what it asserts.

**1. `percentage` reports exactly half the true share.** Its denominator is the sum of
every value in `included` — and `included` contains the `Generación total` row — so the
denominator is exactly twice the real total. Verified on two independent datasets
(2014–2018 yearly, 2024-01 monthly): `sumAll / total` was exactly `2.0` in every period
of both.

| Castilla-La Mancha, 2018 | reported `percentage` | true `value / total` |
|---|---|---|
| Eólica | 18.7% | **37.3%** |
| Nuclear | 17.8% | 35.7% |
| Solar fotovoltaica | 3.7% | 7.3% |

The field is also absolute-valued — Carbón 2016 has `value = -2005.081` and
`percentage = +0.0000472`. It is not decoded at all, so no call site can reach for it by
accident; share is computed as `value / total`.

**2. `attributes.type` contradicts itself on renewability.** Every indicator carries
`Renovable` | `No-Renovable` | `total`. `Residuos no renovables` — non-renewable waste —
is classified `Renovable` by 15 regions and `No-Renovable` by 4. The split follows the
id-family boundary exactly: the plain CCAA ids say `Renovable`, the four `874x` regions
say `No-Renovable`. The minority is the one that is right; the name settles it.

This lands directly on the headline figure the product exists to show:

| Renewable total, 2020–2024 | API's classification | Corrected | Overstated by |
|---|---|---|---|
| País Vasco | 7,373,206 | 5,039,343 | **46.3%** |
| Comunidad de Madrid | 2,739,127 | 2,373,353 | 15.4% |
| Principado de Asturias | 17,778,938 | 15,548,980 | 14.3% |

Renewability therefore comes from our own total `Technology -> Renewability`, with the
API's field used only as a fallback for an `Unrecognised` technology. The field is still
decoded, because its `total` value is what structurally identifies the `Generación total`
row without matching a Spanish display string.

**3. The indicator `id` is not a stable key.** It looks like a far better decode key than
a Spanish title, and it is not: the same technology carries different ids depending on
which id-family the region is served from, offset by exactly 42 (`Eólica` is `10333` in
the 15 plain CCAA regions and `10291` in the four `874x` ones). Decoding is keyed on
`title`.

### What the API does not tell you

- **No units, anywhere.** `attributes.magnitude` is `null` in every captured response and
  there is no other units field. MWh is documentation knowledge that we assert — which is
  why the UI states the unit explicitly rather than implying it.
- **No nulls, anywhere.** Missing data is an **absent array entry**: the series are ragged.
  In a 2014–2018 capture every technology has 5 values except Carbón, which has 3 — it
  simply has no 2017 or 2018 entry. A gap therefore only exists relative to the timeline
  you asked for, which is why the decoder is handed the requested `Period` and emits
  `Missing` itself.
- **No provisional or estimated marker.** The `Reading` type has no `Provisional` variant
  because an unreachable variant costs every `case` a branch.
- **Values can be negative** — Carbón, Castilla-La Mancha, 2016 is `-2005.081`. Any smart
  constructor rejecting negative energy would reject the API's own output.
- **Two `last-update` timestamps**, and they differ: one on `data.attributes`, one per
  indicator (2019-06-12 vs 2019-06-20 in the same response). We show the document-level
  one — it is one value per response, where the indicator-level ones would mean picking a
  winner among nine and then captioning the tie-break rather than the data. It is the
  older of the two, so freshness is under-reported rather than over-reported, which is
  the direction that fails safe.

### Limits, errors and rate limiting

**There is no rate limiting.** Across 12 serial requests and two rounds of 20 parallel
requests: no `429`, no `Retry-After`, no rate-limit headers of any kind. **Latency is the
real constraint**, and it degrades sharply under concurrency:

| | |
|---|---|
| upstream cache hit | ~0.2 s |
| cache miss, serial | 1.1 – 5.3 s |
| cache miss, 20 in parallel | 15 – 23 s |

Twenty concurrent requests made everything roughly 10× slower, so the proxy caches and
does not fan out.

**Only `month` and `year` work per autonomous community.** `hour` returns 400 and `day`
returns 500 at `geo_limit=ccaa`; `day` works nationally, tested at both a 7-day and a
2-month range, so it is unsupported rather than range-limited. This is why the domain's
granularity type has two variants and not four — modelling states the API cannot produce
means writing branches the compiler will demand and nothing can ever reach.

**Date ranges are capped, undocumented, and the cap differs per aggregation:** 5 years for
`time_trunc=year` (2014–2018 passes, 2014–2019 returns 400) and 24 months for
`time_trunc=month` (2023-01–2024-12 passes, 2022-12–2024-12 returns 400). Not a uniform
datapoint cap and not a uniform day cap. The consequence is architectural: a comparison
fetches **one request per period** rather than one spanning both, since comparing 2015 to
2024 would exceed the cap while two single-year requests always succeed. It also keeps
each period's load state independent, so one period failing does not blank the other.

**Error bodies are not consistently JSON.** An invalid `geo_ids` and an unsupported
`time_trunc=hour` return a JSON `errors[]` envelope; `time_trunc=day` at CCAA level
returns an **HTML** Symfony error page. Nothing in the client may assume an error body
parses as JSON — which is why `Api.Request.interpretResponse` binds the error body to `_`
and never reads it. A decode failure means exactly one thing: a 2xx whose body did not
match the expected shape.

**An unknown `geo_id` returns 502, not 404**, and those 502s are cached upstream — a
repeated bad id comes back in 0.33 s. A 502 is therefore a stable property of an id, not
a transient failure, despite its `detail` text reading *"Inténtelo de nuevo más tarde"*.
That message is misleading and is never surfaced to the user.

**CORS: the header is present.** `access-control-allow-origin: *` is sent both with and
without an `Origin` request header, so a browser-based Elm app *can* call REData directly
and the proxy is **not** what makes cross-origin work. But `OPTIONS` preflight returns
**403** (Imperva, HTML body, no CORS headers), so direct browser access works only for
CORS-*simple* requests — `GET` with no custom request headers. That is one added header
away from breaking every request at once. The API also sits behind an Imperva WAF; one
cold request hung for 30 s with zero bytes before a retry returned in 0.2 s, which was
not reproducible and is recorded rather than explained.

## The proxy

`server/main.ts` serves `dist/` and proxies an **allowlisted** subset of REData from the
same origin, so the browser never talks to anything but this app's own host.

Given the findings above, note what the proxy is *not* for: it is **not** needed for CORS.
Upstream sends `access-control-allow-origin: *`, and claiming otherwise in a README is a
factual error a reader can disprove in one `curl`. Three real reasons remain:

1. **Latency.** Upstream cache misses take 2–5 s, and 15–23 s under concurrency. Measured
   locally through this proxy: 13.3 s cold, 0.0009 s warm. It is the single biggest
   user-visible win in the app.
2. **Not shipping an open relay.** The allowlist means this server can only ever be
   pointed at the handful of upstream URLs the app actually uses.
3. **Preflight fragility.** Upstream `OPTIONS` returns 403, so direct browser access
   survives only as long as the app sends no custom request headers. Our own origin
   removes that failure mode rather than staying one line of code away from it.

**The allowlist.** Language, category, widget and every query parameter are validated
against literal allowlists, and unknown parameters are rejected outright rather than
ignored. The upstream query string is **rebuilt from scratch in sorted order** rather than
forwarded: nothing unrecognised can reach upstream, and the cache key is canonical
regardless of the order the client sent parameters in. `time_trunc` is restricted to
`month` and `year`, because those are the only aggregations that work at CCAA level. No
client headers are forwarded — upstream needs none, and forwarding them is how a proxy
accidentally leaks cookies to a third party.

**The cache** is an in-process `Map` keyed by the canonical query string. Deno Deploy runs
multiple short-lived isolates, so it is best-effort **per isolate** — never shared, never
guaranteed. It is a latency optimisation, not a correctness mechanism, and no hit rate is
claimed for it here because none can be demonstrated. Only successful responses are
cached: an upstream 502 is stable rather than transient, but caching failures would make
a genuine outage sticky.

**Errors pass through** with their real status code and their real content type rather
than being flattened to a 500 or forced to JSON — upstream is not consistently JSON, and
the client needs to be able to tell a decode failure from an upstream failure.

**The SPA fallback** serves `index.html` for unmatched paths **only when the request
accepts HTML**. A missing `.js` or `.css` must stay a 404, or a typo in an asset path
silently returns HTML and the browser reports a baffling syntax error instead of a
missing file.

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

**Deno is the only runtime — Node is never invoked — and `deno.json` is the only
manifest.** Vite, Tailwind and the Elm compiler are npm packages, declared as `npm:`
specifiers in the `imports` map; `deno install` reads them and materialises
`node_modules/` and the `.bin/` shims the tasks run. Nothing under `src/` imports
any of them, so the import map is doing duty as a dependency list rather than
resolving anything — the price of one manifest instead of two.

`package.json` and `package-lock.json` were both removed as redundant: `deno.lock`
already pins all 146 npm packages, including the platform-specific compiler
binaries, and dropping the second manifest changes nothing downstream, since Vite
resolves its plugins out of `node_modules` and never consults the import map. What
is lost is the `dependencies`/`devDependencies` split and the tools that key off
`package.json` — GitHub's dependency graph, Dependabot — which is the reason to put
it back if this ever grows a CI pipeline that wants them.

The config is `vite.config.mjs` rather than `.js`. Vite bundles the config with
esbuild and parses it as ESM either way, so the extension is not what makes the
build work; it is there because `"type": "module"` went with `package.json`, and
without it an editor's TypeScript service reads a bare `.js` as CommonJS.

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

## Licence

MIT — see [LICENSE](LICENSE).
