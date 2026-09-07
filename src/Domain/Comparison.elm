module Domain.Comparison exposing
    ( Comparison
    , Direction(..)
    , Side
    , TechnologyDelta
    , absoluteChange
    , byChange
    , byDifference
    , changeIn
    , direction
    , percentChange
    , sideIn
    )

import Domain.Breakdown as Breakdown exposing (Breakdown, TechnologyReading)
import Domain.Measure as Measure exposing (Measure(..), Quantity(..))
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
    deltas a b
        |> List.sortWith (\x y -> byMagnitude x.change y.change)


{-| The same rows, ordered by the column the reader is actually looking at.

`byDifference` orders by MWh magnitude, and under `Share` that ordering is a claim the
visible column does not support. The two measures divide by different denominators, so
the biggest mover in MWh is routinely not the biggest mover in percentage points — a
technology can grow by 400 GWh in a year when total generation grew faster, and lose
share while topping the MWh ordering.

The fork is to re-sort per measure (the order matches the column; the rows move when the
toggle is clicked) or to keep one order across both (the rows hold still; the stated
ordering stops being true in one of the two modes). Re-sorting, because the ordering
_is_ the finding — that argument is `byDifference`'s whole doc comment — and an order
that quietly stops meaning what it says is the plausible-looking wrong answer this
project exists not to produce. The cost is real but small: rows move only in direct
response to the user clicking the toggle, and the toggle is the one control on screen
whose entire job is to change what "biggest" means.

Unknown changes still sort last in both modes, for the reason `byDifference` gives.

-}
byChange : Measure -> Breakdown -> Breakdown -> List TechnologyDelta
byChange measure a b =
    case measure of
        Energy ->
            byDifference a b

        Share ->
            deltas a b
                |> List.map (\delta -> ( sharePoints (sideIn a delta.readingA) (sideIn b delta.readingB), delta ))
                |> List.sortWith (\( x, _ ) ( y, _ ) -> byMagnitude x y)
                |> List.map Tuple.second


{-| The union of both periods' technologies, each paired with its two readings. Ordering
is the caller's business; this is the part `byDifference` and `byChange` share.
-}
deltas : Breakdown -> Breakdown -> List TechnologyDelta
deltas a b =
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


{-| Largest magnitude first, unknowns last. Takes the two change values rather than the
two deltas, because under `Share` the value being ordered by is not the delta's `change`
field — it is a percentage-point figure computed from both breakdowns' totals.
-}
byMagnitude : Maybe Float -> Maybe Float -> Order
byMagnitude x y =
    case ( x, y ) of
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


{-| The sign of a change, as a word.

Takes a `Float`, not a `Maybe Float`, and that is the whole of the design. The obvious
signature `Maybe Float -> Direction` has to answer `Nothing` with something, and every
available answer is a lie: `Flat` would make "this technology did not move" and "we have
no figure for this technology in one of the two periods" render identically, which is
the gap-reads-as-a-zero failure in its purest form. Widening `Direction` with a fourth
`Unknown` variant would fix the lie and move the decision nowhere useful — every caller
would still have to word it, and would have two places to do so.

So the missing case never arrives here. A caller holding a `Maybe` uses `Maybe.map`, and
a caller that has already dispatched on why the change is absent — which is what the view
must do anyway, since only it knows the period names to put in the sentence — calls this
with the number it has.

-}
direction : Float -> Direction
direction value =
    if value > 0 then
        Up

    else if value < 0 then
        Down

    else
        Flat


{-| One side of a comparison: a reading together with the total it is a share of.

The pairing is load-bearing. A share delta needs **two** denominators — period A's total
generation and period B's — and the two are different numbers. Four bare `Reading`
arguments in a row would put "divide B's figure by A's total" one transposition away, and
the result of that mistake is not a crash or a `Nothing`; it is a percentage-point figure
that looks entirely reasonable and is wrong by however much total generation moved.

`total` is always the `Breakdown.total` field, never a sum of `technologies` — see
`Domain.Breakdown` for why those two differ — which is what `sideIn` exists to enforce.

-}
type alias Side =
    { reading : Reading
    , total : Reading
    }


{-| Builds a `Side` from the breakdown the reading came out of, so a reading and its
denominator cannot be drawn from different periods.
-}
sideIn : Breakdown -> Reading -> Side
sideIn breakdown reading =
    { reading = reading, total = breakdown.total }


{-| The change between two sides, in the unit the reader is currently looking at.

**Why this is here and not in the view.** Under `Energy` it is `absoluteChange`, already
in this module and already tested. Under `Share` it is the subtraction of two derived
numbers against two different denominators, each guarded for a zero or absent total —
several ways to be quietly wrong, none of them visible in the output. Arithmetic on
`Quantity` floats in a view function would put exactly that where no test reaches it, and
where the next reader cannot tell a right denominator from a wrong one by looking.

**Why `Maybe Quantity` and not `Displayable`.** `Displayable`'s two failure variants
describe a _reading_: `NoMeasurement` means this reading is absent. A change has a
different failure vocabulary — "measured in 2016 only" — and wording it needs the period
names, which this module does not have and should not take as arguments in order to build
a sentence. So the caller dispatches on the two readings for that case, and the `Nothing`
that survives a pair of `Measured` readings means one thing only: the share was
undefined.

The result is a `Quantity`, so `PercentagePoints` and `Percentage` cannot be confused at
the point of rendering, which is the whole reason the former variant exists.

-}
changeIn : Measure -> Side -> Side -> Maybe Quantity
changeIn measure a b =
    case measure of
        Energy ->
            absoluteChange a.reading b.reading
                |> Maybe.map Megawatthours

        Share ->
            sharePoints a b
                |> Maybe.map PercentagePoints


{-| B's share minus A's share, in percentage points.

Each side goes through `Measure.share` against **its own** period's total, so the
zero-and-missing-denominator guard is the same one every share on screen passes through
rather than a second copy of it here. `Maybe.map2` then makes the whole thing `Nothing`
if either share is undefined, which is right: there is no percentage-point difference
between a share and a non-share.

-}
sharePoints : Side -> Side -> Maybe Float
sharePoints a b =
    Maybe.map2 (-)
        (Measure.share b.total b.reading)
        (Measure.share a.total a.reading)
