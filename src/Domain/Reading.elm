module Domain.Reading exposing
    ( Aggregate(..)
    , Reading(..)
    , aggregateToMaybe
    , comparable
    , isMissing
    , sum
    , toMaybe
    )

{-| A single measurement, which may not exist.

Two variants, not three. A `Provisional Float` variant was considered; there is **no
provisional or estimated marker anywhere in any captured response**, so that variant
would be unreachable and would cost every `case` in the codebase a dead branch.

There is also no smart constructor rejecting negative values, because **real data is
negative** — Carbón in Castilla-La Mancha in 2016 is `-2005.081` (pumped storage and
station self-consumption net out below zero). A validating constructor here would
reject the API's own output.

-}


{-| `Missing` is a distinct fact from `Measured 0`, and the whole application depends on
never conflating them. A region that generated no wind is not the same as a region
where wind was not measured.

Note how `Missing` arises: **not** from a `null`. There are no nulls anywhere in any
captured response. A gap is an _absent array entry_ — the series are ragged, and a gap
exists only relative to the timeline we asked for. That is why the decoder takes the
requested `Period` and reconstructs `Missing` itself; see `Api.Decode`.

-}
type Reading
    = Measured Float
    | Missing


toMaybe : Reading -> Maybe Float
toMaybe reading =
    case reading of
        Measured value ->
            Just value

        Missing ->
            Nothing


isMissing : Reading -> Bool
isMissing reading =
    case reading of
        Measured _ ->
            False

        Missing ->
            True


{-| The result of summing readings that may contain gaps.

This type exists because `sum : List Reading -> Reading` is a trap. If any reading is
`Missing`, adding up only the present ones and returning `Measured` silently understates
the total — which is the "collapse a gap to zero" mistake committed one level up, where
it is much harder to see. A headline figure that quietly omits two technologies is
exactly the kind of confident wrong number this project exists to avoid.

So the aggregate reports its own completeness, and the view is forced to acknowledge it:
`Partial` can render as "12,345 MWh (2 of 9 technologies not measured)".

-}
type Aggregate
    = Complete Float
    | Partial { known : Float, missing : Int }
    | NoData


sum : List Reading -> Aggregate
sum readings =
    let
        known =
            List.filterMap toMaybe readings

        missing =
            List.length readings - List.length known
    in
    if List.isEmpty known then
        NoData

    else if missing == 0 then
        Complete (List.sum known)

    else
        Partial { known = List.sum known, missing = missing }


{-| For arithmetic that needs a number and has already accounted for completeness.
Deliberately not called `withDefault 0` — there is no sensible default.
-}
aggregateToMaybe : Aggregate -> Maybe Float
aggregateToMaybe aggregate =
    case aggregate of
        Complete value ->
            Just value

        Partial { known } ->
            Just known

        NoData ->
            Nothing


{-| An aggregate as a single `Reading`, in which **only `Complete` counts as a
measurement**.

This is the conversion to reach for before subtracting two aggregates, and
`aggregateToMaybe` above is not. `aggregateToMaybe (Partial { known }) = Just known` is
right for _displaying_ a headline figure beside its own "2 of 9 not measured" caveat,
and wrong for differencing two of them: the two sides may be missing different
technologies, so `knownB - knownA` is a difference between two differently shaped
subsets. It renders as a change in generation when part of it is a change in coverage —
the exact mistake `Aggregate` was introduced to prevent, committed one level up where
the caveat next to each figure no longer travels with the arithmetic.

`Partial` and `NoData` therefore collapse to the same `Missing` here. Not because they
are the same fact — they are not, and the view words them apart — but because neither is
a number anyone may subtract.

-}
comparable : Aggregate -> Reading
comparable aggregate =
    case aggregate of
        Complete value ->
            Measured value

        Partial _ ->
            Missing

        NoData ->
            Missing
