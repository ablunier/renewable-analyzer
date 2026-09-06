module Api.Decode exposing (breakdown)

{-| The boundary. Everything REData sends becomes a `Domain.Breakdown` here, or it
becomes a decode error — nothing in between, and nothing downstream re-checks.

Two things about this module's signature are worth stating before any of the field
plumbing, because they are the decisions rather than the mechanics.

**It is `Region -> Period -> Decoder Breakdown`, not `Decoder Breakdown`.** A
`Breakdown` has five fields and the response carries two of them. The region appears
_nowhere_ in the body — `data.attributes.title` is the widget name
(`"Generación por tecnología"`) and is byte-identical for every region; a full-body
grep for the region name returns zero matches. The period is likewise only implied by
the datetimes. Both are properties of the **request**, so the decoder takes them as
arguments and stamps them onto the result.

**It is given the `Period` so it can emit `Missing` itself.** `Domain.Reading`'s doc
comment names this module as the place that reconciliation happens. Missing data in
REData is not a `null` — there are no nulls anywhere in any capture — it is an _absent
array entry_. A gap therefore only exists relative to a timeline someone asked for, so
the only layer that can tell "genuinely not measured" apart from "not in this response
because we did not ask for it" is the one holding the request. Above this line, a
sparse unaligned value is unrepresentable.

-}

import Domain.Breakdown exposing (Breakdown, TechnologyReading)
import Domain.Period as Period exposing (Period)
import Domain.Reading exposing (Reading(..))
import Domain.Region exposing (Region)
import Domain.Technology as Technology exposing (Renewability(..))
import Json.Decode as Decode exposing (Decoder)


{-| Only two things are actually read out of the JSON, which is why this is a `map2`
and not a pipeline.

`NoRedInk/json-decode-pipeline` earns its place when a record has eight or ten fields
and `mapN` runs out or becomes unreadable positionally. Here the widest record is three
fields wide, so `map2`/`map3` from `elm/json` cover it without a dependency — and
`mapN` has one property the pipeline style loses: adding a field to the record breaks
the call at compile time instead of silently leaving it un-decoded.

-}
breakdown : Region -> Period -> Decoder Breakdown
breakdown region period =
    Decode.map2 (assemble region period)
        lastUpdate
        (Decode.field "included" (Decode.list (indicator period)))


{-| **Decision: `data.attributes.last-update`, not the per-indicator one.**

There are two timestamps in every response and they differ — 2019-06-12 on `data`
versus 2019-06-20 on each indicator in the 2014–2018 capture. `Breakdown` has one
`lastUpdate` field, so one of them has to win.

The document-level one wins because it is _one value per response_. The indicator-level
timestamps are one per technology, so showing "the" last update would mean picking a
winner among nine — max? min? the total row's? — and every choice needs a caption
explaining itself. A single response-level timestamp needs only the caption it already
deserves: what it refers to.

-}
lastUpdate : Decoder String
lastUpdate =
    Decode.at [ "data", "attributes", "last-update" ] Decode.string


{-| Routing the total row out happens **here in Elm, not in the decoder**, and that is
deliberate.

The alternative is `Decode.andThen` on `attributes.type` to choose a different decoder
per row — the standard tagged-union pattern. It does not fit: both row kinds have
byte-identical shape, so there is nothing different to _decode_. The type field decides
where a decoded row is _sent_, which is a classification over the finished list. Keeping
it out of the decoder leaves the decoder describing shape only, and leaves this a plain
total function over a list.

-}
assemble : Region -> Period -> String -> List Indicator -> Breakdown
assemble region period updated indicators =
    { region = region
    , period = period
    , lastUpdate = updated
    , total =
        indicators
            |> List.filterMap totalReading
            |> List.head
            |> Maybe.withDefault Missing
    , technologies = List.filterMap technologyReading indicators
    }



-- INDICATORS


type alias Indicator =
    { role : Role
    , title : String
    , reading : Reading
    }


{-| The `Generación total` row is identified **structurally**, by
`attributes.type == "total"`, and never by matching the title string.

`Domain.Technology`'s doc comment is where the consequence lives: there is no `Total`
variant, because a total row that leaked into the technology list would double-count
every sum in the application. That is not a hypothetical failure — it is exactly the
bug in the API's own `percentage` field, whose denominator includes the total row and
which therefore reports half of every true share.

-}
type Role
    = TotalRow
    | GenerationRow Renewability


indicator : Period -> Decoder Indicator
indicator period =
    Decode.field "attributes"
        (Decode.map3 Indicator
            (Decode.field "type" role)
            (Decode.field "title" Decode.string)
            (Decode.field "values" (reading period))
        )


{-| `andThen` rather than a lookup returning a default: an unrecognised value here
fails the whole response.

**This is a genuine fork and the strict side is not obviously right.** The lenient
alternative — treat anything unknown as a technology row of some default renewability —
keeps the app working through a vocabulary change, at the cost of guessing. Strict wins
because of _which_ guess it would be. Our own `Technology -> Renewability` table
overrides this field for every technology we recognise, so the only thing the field
uniquely decides is whether a row is a **denominator or a numerator**. A new structural
row — a subtotal, a demand series — silently parsed as a technology would inflate every
total in the app by a plausible-looking amount, which is the one failure mode this
whole design is built to prevent. A loud decode error is strictly better than a
confident wrong number.

-}
role : Decoder Role
role =
    Decode.string |> Decode.andThen roleFromString


roleFromString : String -> Decoder Role
roleFromString raw =
    case raw of
        "total" ->
            Decode.succeed TotalRow

        "Renovable" ->
            Decode.succeed (GenerationRow Renewable)

        "No-Renovable" ->
            Decode.succeed (GenerationRow NonRenewable)

        other ->
            Decode.fail
                ("Unknown indicator type \""
                    ++ other
                    ++ "\". Expected \"total\", \"Renovable\" or \"No-Renovable\"."
                )


{-| A response with **no total row at all** yields `Missing`, not a decode failure.

That is a fork, and the type settles it. `Breakdown.total` is a `Reading`, not a
`Float` — the field already admits "not measured", so absence has a faithful
representation and does not need to be an error. It also keeps the sparse-region
requirement — Ceuta and Melilla must render sensibly rather than break — on the honest
path: the screen says the total was not measured, share renders as `ShareUndefined`,
and nothing divides by zero. Failing the decode instead would report a malformed
response for data that is merely empty.

The cost is real and worth naming: a genuine upstream shape change that dropped the
total row would show as "no data" rather than as an error. That is the trade accepted
here, on the grounds that the empty case is documented and the shape change is
speculative.

-}
totalReading : Indicator -> Maybe Reading
totalReading row =
    case row.role of
        TotalRow ->
            Just row.reading

        GenerationRow _ ->
            Nothing


{-| Keyed on `attributes.title`, never on the numeric `id`. The id is not stable across
regions — the same technology is offset by 42 between id-families, and `Generación
total` is `10338` for fifteen of the regions and `10296` for the four `874x` ones. See
`Domain.Technology.fromTitle`.

`renewability` is resolved rather than stored raw, so the API's field never escapes this
module. `Technology.resolveRenewability` lets our table win where we have one and falls
back to the API only for `Unrecognised` — the field cannot be trusted outright, since it
labels `Residuos no renovables` as `Renovable` in 15 of 19 regions.

-}
technologyReading : Indicator -> Maybe TechnologyReading
technologyReading row =
    case row.role of
        TotalRow ->
            Nothing

        GenerationRow apiSays ->
            let
                technology =
                    Technology.fromTitle row.title
            in
            Just
                { technology = technology
                , renewability = Technology.resolveRenewability technology apiSays
                , reading = row.reading
                }



-- VALUES


type alias DatedValue =
    { datetime : String
    , value : Float
    }


{-| Note what is **not** decoded: `percentage`.

It is not merely unused, it is wrong — its denominator is the sum of every `included`
value, and `included` contains the total row, so it reports exactly half of every true
share, and it is absolute-valued so a negative `value` yields a positive `percentage`.
Share is computed downstream as `value / total.value`. Leaving the field out of the
record means no call site can reach for it by accident.

There is no smart constructor rejecting negatives either: Carbón in Castilla-La Mancha
in 2016 is `-2005.081`, and a validator here would reject the API's own output.

-}
datedValue : Decoder DatedValue
datedValue =
    Decode.map2 DatedValue
        (Decode.field "datetime" Decode.string)
        (Decode.field "value" Decode.float)


{-| The ragged-series reconciliation, and the reason this module takes a `Period`.

The array is filtered down to the bucket we asked for. Absent — because the array is
empty, or because it holds only other periods — is `Missing`, never `Measured 0`. In
the 2014–2018 capture every technology has five values except Carbón, which has three:
asking that response for 2017 must yield `Missing` for Carbón and a real figure for
everything else.

-}
reading : Period -> Decoder Reading
reading period =
    Decode.list datedValue
        |> Decode.map (pick period)


pick : Period -> List DatedValue -> Reading
pick period values =
    values
        |> List.filter (\v -> String.startsWith (bucketLabel period) v.datetime)
        |> List.head
        |> Maybe.map (.value >> Measured)
        |> Maybe.withDefault Missing


{-| Matching is a **string prefix comparison on the calendar date**, and both halves of
that are load-bearing.

_Prefix, not instant._ REData stamps buckets in Madrid local time:
`"2014-01-01T00:00:00.000+01:00"`. Parsed as an instant that is `2013-12-31T23:00Z`, so
anything that converts to UTC before comparing puts every January bucket in the
previous year. The calendar date is REE's own label for the bucket; comparing labels to
labels is the only comparison that means anything here.

_Derived from `Period.startDate`, not rebuilt._ Taking the first ten characters of the
same string the request was built from means the match key and the request cannot drift
apart. Writing `String.fromInt y ++ "-01-01"` here instead would be a second, private
copy of `Period`'s date arithmetic — correct today and free to rot.

-}
bucketLabel : Period -> String
bucketLabel period =
    String.left 10 (Period.startDate period)
