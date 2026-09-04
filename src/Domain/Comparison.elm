module Domain.Comparison exposing
    ( Comparison
    , Direction(..)
    , TechnologyDelta
    , absoluteChange
    , byDifference
    , direction
    , percentChange
    )

import Domain.Breakdown as Breakdown exposing (Breakdown, TechnologyReading)
import Domain.Measure exposing (Measure)
import Domain.Period as Period
import Domain.Reading exposing (Reading(..))
import Domain.Region exposing (Region)
import Domain.Technology exposing (Renewability, Technology)


{-| The application's central concept, given a name in the type system.

Note what it is: the _question_, not the answer. Region, the two periods, and the
measure — everything the user chose. The answer is two `Breakdown`s, held separately in
the model as independent `RemoteData` so that one period failing to load does not blank
the other.

`periods` is a `Period.Pair`, so a `Comparison` comparing a year to a month cannot be
constructed. There is no validation step here and no `Result`; the guarantee is in the
type.

-}
type alias Comparison =
    { region : Region
    , periods : Period.Pair
    , measure : Measure
    }


type Direction
    = Up
    | Down
    | Flat


{-| One technology's before/after, plus the change between them.

`change` is a `Maybe` and that is the honest type. If either side is `Missing` there is
no defensible delta — the difference between a measurement and a non-measurement is not
a number. Returning `0`, or treating the gap as zero and reporting the full value as the
change, would be inventing data.

-}
type alias TechnologyDelta =
    { technology : Technology
    , renewability : Renewability
    , readingA : Reading
    , readingB : Reading
    , change : Maybe Float
    }


{-| **Sorted by the magnitude of the change, largest first.** This ordering _is_ the
workflow design decision.

An alphabetical list makes the reader scan for what moved. A list ordered by size makes
the reader scan past the big-but-static technologies. Ordering by the size of the
difference puts the technology that explains the change at the top, which is the actual
question — "which technologies account for the difference?"

Technologies whose change is unknown sort last rather than first. They are not evidence
of a large movement; they are an absence of evidence, and putting them at the top would
promote missing data over the finding.

The technology set is the **union** of both periods, not the intersection. A technology
that appears in one period and not the other is a real and interesting event — Carbón
disappears from the data after 2016 — and intersecting would hide exactly that.

-}
byDifference : Breakdown -> Breakdown -> List TechnologyDelta
byDifference a b =
    let
        namesInA =
            List.map .technology a.technologies

        onlyInB =
            List.filter
                (\t -> not (List.member t.technology namesInA))
                b.technologies
    in
    (a.technologies ++ onlyInB)
        |> List.map (deltaFor a b)
        |> List.sortWith byChangeMagnitude


{-| Takes the `TechnologyReading` the technology was found in, not a bare `Technology`.

That is what lets `renewability` be read straight off the source row. Threading a bare
`Technology` through instead would mean looking the classification up again and
supplying a default for "found in neither period" — a branch that cannot happen, since
the technology came from the union of the two. An unreachable default is a small lie
about what the code can do, and the compiler cannot tell you it is dead.

The `Maybe.withDefault Missing` below is a different matter and is honest: a technology
genuinely absent from one period's response has no reading for that period.

-}
deltaFor : Breakdown -> Breakdown -> TechnologyReading -> TechnologyDelta
deltaFor a b source =
    let
        readingIn breakdown =
            Breakdown.find source.technology breakdown
                |> Maybe.map .reading
                |> Maybe.withDefault Missing

        readingA =
            readingIn a

        readingB =
            readingIn b
    in
    { technology = source.technology
    , renewability = source.renewability
    , readingA = readingA
    , readingB = readingB
    , change = absoluteChange readingA readingB
    }


byChangeMagnitude : TechnologyDelta -> TechnologyDelta -> Order
byChangeMagnitude x y =
    case ( x.change, y.change ) of
        ( Just a, Just b ) ->
            compare (abs b) (abs a)

        ( Just _, Nothing ) ->
            LT

        ( Nothing, Just _ ) ->
            GT

        ( Nothing, Nothing ) ->
            EQ


{-| B minus A, in MWh. `Nothing` when either side was not measured.
-}
absoluteChange : Reading -> Reading -> Maybe Float
absoluteChange readingA readingB =
    case ( readingA, readingB ) of
        ( Measured a, Measured b ) ->
            Just (b - a)

        _ ->
            Nothing


{-| Relative change, guarded against a zero baseline.

`Nothing` covers two distinct-but-equally-unreportable cases: a missing reading, and a
baseline of zero where the percentage change is undefined rather than infinite. A region
that generated no solar in period A and some in period B has not increased by "Infinity
percent"; it has gone from nothing to something, which the absolute figure states
perfectly well.

-}
percentChange : Reading -> Reading -> Maybe Float
percentChange readingA readingB =
    case ( readingA, readingB ) of
        ( Measured a, Measured b ) ->
            if a == 0 then
                Nothing

            else
                Just ((b - a) / abs a * 100)

        _ ->
            Nothing


direction : Maybe Float -> Direction
direction change =
    case change of
        Just value ->
            if value > 0 then
                Up

            else if value < 0 then
                Down

            else
                Flat

        Nothing ->
            Flat
