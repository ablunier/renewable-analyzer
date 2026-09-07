module View.Figures exposing (viewComparison, viewSinglePeriod)

{-| The tables of numbers: one period's figures on their own, and two periods with the
change between them.

Both live here because they are the same table at two widths — the comparison shows the
same per-technology figures in its first two columns and adds a third — and because
`viewAggregate` is shared between them. Splitting them apart would push that sharing
across a module boundary and make one of the two the owner of a helper the other needs
just as much.

As in `View.Value`, everything here is `Html msg`. These tables render a `Breakdown`;
they never ask for one. Retrying a failed request, picking a year and toggling the
measure are `Main`'s business, and none of the three is reachable from a cell — so the
`RemoteData` fork stays in `Main.viewFigures`, which decides _whether_ there is a
comparison to draw, and this module only draws it.

-}

import Domain.Breakdown as Breakdown exposing (Breakdown, TechnologyReading)
import Domain.Comparison as Comparison exposing (TechnologyDelta)
import Domain.Measure as Measure exposing (Measure(..))
import Domain.Period as Period exposing (Period)
import Domain.Reading as Reading exposing (Aggregate(..), Reading(..))
import Domain.Region as Region
import Domain.Technology as Technology exposing (Renewability(..))
import Html exposing (Html, caption, div, h2, p, section, span, table, tbody, td, text, thead, tr)
import Html.Attributes exposing (class)
import View.Value exposing (columnHeading, gap, numericColumnHeading, renewabilityLabel, rowHeading, signed, viewDisplayable, viewSignedQuantity)



-- SINGLE PERIOD


{-| One period's own figures, for the halves of the screen where there is no second
period to subtract.

Rows keep the order REData returned them in, rather than being sorted by size. There is
no "what moved" to sort by here — that ordering is `byChange`'s whole argument and it
needs two periods — and REData's order is stable across regions and years, so the rows
do not rearrange themselves when the user changes the year of a slot that is already on
screen.

-}
viewSinglePeriod : Measure -> Breakdown -> Html msg
viewSinglePeriod measure breakdown =
    div [ class "space-y-4" ]
        [ table [ class "w-full text-sm" ]
            [ caption [ class "pb-1 text-left text-xs font-medium uppercase tracking-wide text-slate-500" ]
                [ text "Headline" ]
            , tbody []
                [ headlineRow measure breakdown Renewable
                , headlineRow measure breakdown NonRenewable
                ]
            ]
        , table [ class "w-full text-sm" ]
            [ caption [ class "pb-1 text-left text-xs font-medium uppercase tracking-wide text-slate-500" ]
                [ text "By technology" ]
            , thead []
                [ tr [ class "border-b border-slate-300" ]
                    [ columnHeading "Technology"
                    , numericColumnHeading (Period.label breakdown.period)
                    ]
                ]
            , tbody []
                (List.map (singlePeriodRow measure breakdown) breakdown.technologies)
            ]
        ]


headlineRow : Measure -> Breakdown -> Renewability -> Html msg
headlineRow measure breakdown renewability =
    tr [ class "border-b border-slate-100" ]
        [ rowHeading (renewabilityLabel renewability) Nothing
        , td [ class "py-1.5 text-right" ]
            [ viewAggregate measure breakdown renewability ]
        ]


singlePeriodRow : Measure -> Breakdown -> TechnologyReading -> Html msg
singlePeriodRow measure breakdown technologyReading =
    tr [ class "border-b border-slate-100" ]
        [ rowHeading
            (Technology.toName technologyReading.technology)
            (Just (renewabilityLabel technologyReading.renewability))
        , td [ class "py-1.5 text-right" ]
            [ viewDisplayable (Measure.display measure breakdown.total technologyReading.reading) ]
        ]



-- COMPARISON


viewComparison : Measure -> Breakdown -> Breakdown -> Html msg
viewComparison measure a b =
    section [ class "space-y-6 rounded border border-slate-200 p-4" ]
        [ h2 [ class "text-lg font-medium" ] [ text (comparisonHeading measure a b) ]
        , viewHeadlines measure a b
        , viewTechnologyTable measure a b
        ]


{-| "Galicia · 2023 → 2025 · MWh" — the three things every figure below is relative to.

The region is read off `a`, not off `model.region`, and the difference is not cosmetic.
A region change puts every asked slot back to `Loading`, so two `Success` breakdowns can
never straddle two regions and the two agree by construction; but reading it from the
data means the heading names the region the numbers came from rather than the one the
control happens to be showing. If those ever disagree, the numbers are what the reader
needs named.

-}
comparisonHeading : Measure -> Breakdown -> Breakdown -> String
comparisonHeading measure a b =
    String.join " · "
        [ Region.toName a.region
        , Period.label a.period ++ " → " ++ Period.label b.period
        , Measure.axisLabel measure
        ]


viewHeadlines : Measure -> Breakdown -> Breakdown -> Html msg
viewHeadlines measure a b =
    table [ class "w-full text-sm" ]
        [ caption [ class "pb-1 text-left text-xs font-medium uppercase tracking-wide text-slate-500" ]
            [ text "Headline" ]
        , thead []
            [ tr [ class "border-b border-slate-300" ]
                [ columnHeading ""
                , numericColumnHeading (Period.label a.period)
                , numericColumnHeading (Period.label b.period)
                , numericColumnHeading (changeColumnLabel measure)
                ]
            ]
        , tbody []
            [ headlineComparisonRow measure a b Renewable
            , headlineComparisonRow measure a b NonRenewable
            ]
        ]


headlineComparisonRow : Measure -> Breakdown -> Breakdown -> Renewability -> Html msg
headlineComparisonRow measure a b renewability =
    tr [ class "border-b border-slate-100" ]
        [ rowHeading (renewabilityLabel renewability) Nothing
        , td [ class "py-1.5 text-right" ] [ viewAggregate measure a renewability ]
        , td [ class "py-1.5 text-right" ] [ viewAggregate measure b renewability ]
        , td [ class "py-1.5 text-right" ] [ viewHeadlineChange measure a b renewability ]
        ]


{-| One headline figure, and its own statement of how complete it is.

`Partial` has to say so in its own cell rather than in a footnote, because the number
beside it is the sum of the technologies that _were_ measured and nothing about the digits
says which ones are missing. "12,345 MWh (2 of 9 technologies not measured)" is
`Domain.Reading`'s own worked example of this, and the denominator — the number of
technologies of this renewability in this response — is counted here rather than carried
in `Aggregate`, because `Aggregate` is the result of summing a list and the list's length
is the caller's to remember.

-}
viewAggregate : Measure -> Breakdown -> Renewability -> Html msg
viewAggregate measure breakdown renewability =
    let
        aggregate =
            aggregateFor renewability breakdown
    in
    div []
        [ viewDisplayable (Measure.displayAggregate measure breakdown.total aggregate)
        , case aggregate of
            Partial { missing } ->
                span [ class "block text-xs text-slate-500" ]
                    [ text
                        ("("
                            ++ String.fromInt missing
                            ++ " of "
                            ++ String.fromInt (countOf renewability breakdown)
                            ++ " technologies not measured)"
                        )
                    ]

            Complete _ ->
                text ""

            NoData ->
                text ""
        ]


aggregateFor : Renewability -> Breakdown -> Aggregate
aggregateFor renewability =
    case renewability of
        Renewable ->
            Breakdown.renewableTotal

        NonRenewable ->
            Breakdown.nonRenewableTotal


countOf : Renewability -> Breakdown -> Int
countOf renewability breakdown =
    breakdown.technologies
        |> List.filter (\t -> t.renewability == renewability)
        |> List.length


{-| The delta between two headline figures — or a sentence saying why there isn't one.

This is the trap `Domain.Reading.comparable` exists for, and it is worth restating at the
call site. `aggregateToMaybe` would hand back a `Partial`'s known part on both sides, and
subtracting those differences two sums taken over possibly different technologies: if
2023 is missing Hidroeólica and 2025 is missing Carbón, the "change" is partly a change
in coverage wearing the units of generation. `comparable` collapses `Partial` and
`NoData` to `Missing`, so only two `Complete` aggregates ever reach the arithmetic, and
everything else is worded.

The wording distinguishes the two reasons, because they are different facts: a `Partial`
period has a figure that is merely incomplete, and a `NoData` period has no figure at
all. Rendering both as a dash would say "zero" in a column where every other cell is a
number.

-}
viewHeadlineChange : Measure -> Breakdown -> Breakdown -> Renewability -> Html msg
viewHeadlineChange measure a b renewability =
    let
        aggregateA =
            aggregateFor renewability a

        aggregateB =
            aggregateFor renewability b

        readingA =
            Reading.comparable aggregateA

        readingB =
            Reading.comparable aggregateB
    in
    case ( readingA, readingB ) of
        ( Measured _, Measured _ ) ->
            case Comparison.changeIn measure (Comparison.sideIn a readingA) (Comparison.sideIn b readingB) of
                Just quantity ->
                    div []
                        [ viewSignedQuantity quantity
                        , viewRelativeChange measure readingA readingB
                        ]

                Nothing ->
                    gap "share undefined"

        _ ->
            gap
                (String.join
                    "; "
                    (List.filterMap identity
                        [ Just "not comparable"
                        , incompleteness a.period aggregateA
                        , incompleteness b.period aggregateB
                        ]
                    )
                )


incompleteness : Period -> Aggregate -> Maybe String
incompleteness period aggregate =
    case aggregate of
        Complete _ ->
            Nothing

        Partial { missing } ->
            Just
                (String.fromInt missing
                    ++ (if missing == 1 then
                            " technology"

                        else
                            " technologies"
                       )
                    ++ " not measured in "
                    ++ Period.label period
                )

        NoData ->
            Just ("nothing measured in " ++ Period.label period)


{-| The relative change beside the absolute one, in energy mode only.

A relative change of a share is the ambiguity that `PercentagePoints` exists to remove:
20% to 25% is +5 pp and +25% relative, and putting both on one line invites the reader
to pick whichever they expected. In share mode the percentage-point figure is the answer
and there is no second number.

`percentChange` returning `Nothing` means exactly one thing at this call site — both
readings are `Measured` here, so a missing reading is already excluded, and the only
remaining cause is a zero baseline. That is "went from nothing to something", not an
infinite increase, and the absolute figure beside it already says how much.

-}
viewRelativeChange : Measure -> Reading -> Reading -> Html msg
viewRelativeChange measure readingA readingB =
    case measure of
        Share ->
            text ""

        Energy ->
            span [ class "block text-xs text-slate-500" ]
                [ text
                    (case Comparison.percentChange readingA readingB of
                        Just percent ->
                            "(" ++ signed 1 percent ++ "% relative)"

                        Nothing ->
                            "(no relative change from a zero baseline)"
                    )
                ]


viewTechnologyTable : Measure -> Breakdown -> Breakdown -> Html msg
viewTechnologyTable measure a b =
    div [ class "space-y-2" ]
        [ table [ class "w-full text-sm" ]
            [ caption [ class "pb-1 text-left text-xs font-medium uppercase tracking-wide text-slate-500" ]
                [ text "By technology" ]
            , thead []
                [ tr [ class "border-b border-slate-300" ]
                    [ columnHeading "Technology"
                    , numericColumnHeading (Period.label a.period)
                    , numericColumnHeading (Period.label b.period)
                    , numericColumnHeading (changeColumnLabel measure)
                    ]
                ]
            , tbody []
                (List.map (technologyRow measure a b) (Comparison.byChange measure a b))
            ]
        , p [ class "text-xs text-slate-500" ] [ text (orderingNote measure) ]
        ]


{-| The change column names its unit in full, and "percentage points" is spelled out
rather than abbreviated to "pp" here. The cells say "pp"; the heading is the one place
with room to disambiguate it from the other percentage on screen, and a reader who has
just switched the toggle to "% of total generation" is exactly the reader who would
otherwise read this column as a relative change.
-}
changeColumnLabel : Measure -> String
changeColumnLabel measure =
    case measure of
        Energy ->
            "Change (MWh)"

        Share ->
            "Change (percentage points)"


orderingNote : Measure -> String
orderingNote measure =
    case measure of
        Energy ->
            "Ordered by the size of the change in MWh, largest first. Technologies with no comparable change are listed last."

        Share ->
            "Ordered by the size of the change in percentage points, largest first. Technologies with no comparable change are listed last."


technologyRow : Measure -> Breakdown -> Breakdown -> TechnologyDelta -> Html msg
technologyRow measure a b delta =
    tr [ class "border-b border-slate-100" ]
        [ rowHeading
            (Technology.toName delta.technology)
            (Just (renewabilityLabel delta.renewability))
        , td [ class "py-1.5 text-right" ]
            [ viewDisplayable (Measure.display measure a.total delta.readingA) ]
        , td [ class "py-1.5 text-right" ]
            [ viewDisplayable (Measure.display measure b.total delta.readingB) ]
        , td [ class "py-1.5 text-right" ]
            [ viewChange measure a b delta ]
        ]


{-| The change cell dispatches on the two **readings** before it asks for a number, and
that ordering is the point.

`Comparison.direction` is never handed a missing value — it cannot be, since it takes a
`Float` — so "did not move" can only mean a change of zero. The three gap cases have to
be worded, and only this function knows the period names to word them with: a technology
that vanished after 2016 reads "measured in 2016 only", not "no change" and not "—",
which in a column of numbers would be read as a zero.

What survives to the last branch, a `Nothing` from two `Measured` readings, is exactly
one thing: the share of a period whose total generation is zero or absent. That is why
`changeIn` returns a `Maybe Quantity` rather than a `Displayable` — its `NoMeasurement`
would be unreachable here, and its wording would have to be re-derived from the readings
anyway.

-}
viewChange : Measure -> Breakdown -> Breakdown -> TechnologyDelta -> Html msg
viewChange measure a b delta =
    case ( delta.readingA, delta.readingB ) of
        ( Missing, Missing ) ->
            gap "not measured in either period"

        ( Missing, Measured _ ) ->
            gap ("measured in " ++ Period.label b.period ++ " only")

        ( Measured _, Missing ) ->
            gap ("measured in " ++ Period.label a.period ++ " only")

        ( Measured _, Measured _ ) ->
            case Comparison.changeIn measure (Comparison.sideIn a delta.readingA) (Comparison.sideIn b delta.readingB) of
                Just quantity ->
                    viewSignedQuantity quantity

                Nothing ->
                    gap "share undefined"
