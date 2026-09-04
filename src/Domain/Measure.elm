module Domain.Measure exposing
    ( Displayable(..)
    , Measure(..)
    , Quantity(..)
    , axisLabel
    , display
    , displayAggregate
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

-}
type Quantity
    = Megawatthours Float
    | Percentage Float


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


{-| The one place a share is ever computed.

Note the guard on the denominator. A zero total is not hypothetical — a sparse system
in a month with no recorded generation gives exactly that, and `x / 0` in Elm yields
`Infinity` or `NaN`, which then renders as the string "Infinity" in the UI rather than
raising.

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

        ( Share, Measured value ) ->
            case total of
                Missing ->
                    ShareUndefined

                Measured totalValue ->
                    -- Elm has no Float literal patterns, so the zero-denominator
                    -- guard is a conditional rather than a third branch.
                    if totalValue == 0 then
                        ShareUndefined

                    else
                        Shown (Percentage (value / totalValue * 100))


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
