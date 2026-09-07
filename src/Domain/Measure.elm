module Domain.Measure exposing
    ( Displayable(..)
    , Measure(..)
    , Quantity(..)
    , amount
    , axisLabel
    , display
    , displayAggregate
    , share
    , toggle
    , unitLabel
    )

import Domain.Reading as Reading exposing (Aggregate, Reading(..))


{-| Absolute energy vs share of total generation.

**`Measure` is a view concern, not a property of the data.** One request returns one set
of MWh numbers; share is _derived_ from them by dividing by `Generación total`. There is
no such thing as a "percentage series" arriving from the API, so modelling `Measure` as
something that distinguishes two kinds of series would invent a fetch that does not
exist.

The acceptance test still holds — "impossible to compile a call that renders a
percentage series with an MWh axis label" — but it is achieved by pairing each _value_
with its unit in `Quantity`, rather than by duplicating the series type. You cannot hold
a bare `Float` that has lost track of whether it is MWh or a percentage.

**The share denominator is total generation, not renewable generation**. "Renewables were
45% of generation" is the figure an analyst quotes, it uses the row REE already ships, and
it keeps one denominator across the whole screen.

-}
type Measure
    = Energy
    | Share


{-| A number that knows its own unit. This is the type that makes the acceptance test
compile-time: `unitLabel` is a function of the `Quantity`, so a value and its unit
cannot be separated and re-paired wrongly.

We hardcode MWh. That is not laziness: `attributes.magnitude` is `null` in every
captured response and **there is no units field anywhere** in the API. MWh is
documentation knowledge that we assert — which is why the view must state the unit
explicitly rather than leaving it implied.

`PercentagePoints` is the unit of a **difference between two shares**, and it is a third
variant rather than a reuse of `Percentage` because the two are not the same number.
Going from 20% to 25% is `+5` percentage points and also `+25%` relative, and a value
that says only "%" cannot say which of those it is. Carrying the distinction in the type
means `unitLabel` answers it, so a percentage-point figure cannot be printed under a "%"
label by someone forgetting to special-case it.

It is reachable, which is the bar this codebase sets for a variant: `Comparison.changeIn`
in `Share` mode is its only constructor and a change column is its only reader. `display`
never produces one — the share of a single reading is a `Percentage` — so the two live
side by side without either being dead.

-}
type Quantity
    = Megawatthours Float
    | Percentage Float
    | PercentagePoints Float


{-| What the view is actually handed. Three outcomes, all of them real, and each has to
render differently.

`NoMeasurement` and `ShareUndefined` are kept apart on purpose. "We have no reading for
this technology in this period" and "a share of zero total generation has no meaning"
are different facts about the world, and a sparse system like Ceuta or Melilla produces
both. Collapsing them into one `Nothing` — or worse, into `0%` — would tell the reader
a gap is a zero, which is the one thing this model is built not to do.

-}
type Displayable
    = Shown Quantity
    | NoMeasurement
    | ShareUndefined


toggle : Measure -> Measure
toggle measure =
    case measure of
        Energy ->
            Share

        Share ->
            Energy


{-| The chart's axis label. Derived from `Measure` because an axis exists before any
value does; per-value units come from `unitLabel` instead.
-}
axisLabel : Measure -> String
axisLabel measure =
    case measure of
        Energy ->
            "MWh"

        Share ->
            "% of total generation"


unitLabel : Quantity -> String
unitLabel quantity =
    case quantity of
        Megawatthours _ ->
            "MWh"

        Percentage _ ->
            "%"

        PercentagePoints _ ->
            "pp"


{-| The bare number, for a caller that has to format it.

Not a hole in the unit guarantee. `unitLabel` takes the same `Quantity`, so the only way
to separate a value from its unit is to call this and then not call that — a discipline
kept in one rendering function (`Main.formatQuantity`) rather than spread across every
call site. The alternative, a `format : Quantity -> String` in the domain, would put
thousands separators and decimal places — presentation choices with no domain meaning —
inside the domain.

-}
amount : Quantity -> Float
amount quantity =
    case quantity of
        Megawatthours value ->
            value

        Percentage value ->
            value

        PercentagePoints value ->
            value


{-| One reading, ready to render under the measure the reader has chosen.

The share arithmetic and its zero-denominator guard live in `share` below, which is the
one place a share is ever computed; this function's job is to turn its `Maybe` into the
three-way `Displayable` a cell needs. A missing _reading_ is `NoMeasurement` before the
measure is even consulted, which is why the first branch comes first: "we have no figure
for this technology" is true in both measures and must not be reported as an undefined
share.

We compute share ourselves and never decode the API's `percentage` field: that field's
denominator includes the `Generación total` row, making it exactly twice the real total,
so every reported share is exactly half the truth. It is also absolute-valued, so a
negative generation value yields a positive percentage.

-}
display : Measure -> Reading -> Reading -> Displayable
display measure total reading =
    case ( measure, reading ) of
        ( _, Missing ) ->
            NoMeasurement

        ( Energy, Measured value ) ->
            Shown (Megawatthours value)

        ( Share, Measured _ ) ->
            case share total reading of
                Just percentage ->
                    Shown (Percentage percentage)

                Nothing ->
                    ShareUndefined


{-| The share itself, unwrapped, for the one caller that needs to do arithmetic with it
rather than show it: `Comparison.changeIn` differences two shares computed against two
different periods' totals.

Split out of `display` rather than duplicated inside `Comparison`, so that "the one place
a share is ever computed" stays literally true — including the zero-denominator guard,
which is the part that is silently wrong everywhere it is reimplemented.

`Nothing` is the same fact `display` reports as `ShareUndefined`: a missing or zero
denominator, or nothing to divide. It is a `Maybe` here rather than a `Displayable`
because this returns a number to compute with, not something to put on screen.

-}
share : Reading -> Reading -> Maybe Float
share total reading =
    case ( total, reading ) of
        ( Measured totalValue, Measured value ) ->
            -- Elm has no Float literal patterns, so the zero-denominator guard is a
            -- conditional rather than a third branch.
            if totalValue == 0 then
                Nothing

            else
                Just (value / totalValue * 100)

        _ ->
            Nothing


{-| Same rule applied to a summed figure, so the headline number goes through the same
zero-denominator and missing-data guards as an individual cell.
-}
displayAggregate : Measure -> Reading -> Aggregate -> Displayable
displayAggregate measure total aggregate =
    case Reading.aggregateToMaybe aggregate of
        Nothing ->
            NoMeasurement

        Just value ->
            display measure total (Measured value)
