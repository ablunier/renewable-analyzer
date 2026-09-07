module Main exposing (main)

{-| One region, two periods, two independent requests, one comparison between them.

The user picks a region, a year for period A, a year for period B, and whether to read
the figures as energy or as share of total generation. Each slot's answer is its own
`RemoteData`, so one period failing to load leaves the other on screen — the shape
`Domain.Comparison`'s doc comment describes as "two `Breakdown`s, held separately in the
model as independent `RemoteData`". The comparison is computed from the two of them
where both have arrived, and nowhere else.

**Why `Model` still holds loose fields rather than a `Comparison`.** The previous
revision of this comment predicted that a `Comparison` would arrive with the measure
toggle and the view consuming it, on the grounds that both of the standing objections —
no `Pair` while B is unpicked, no `measure` anywhere — would lift together. The measure
half did lift and is a field below. The `Pair` half did not, and a third objection
turned up on the way.

No function anywhere takes a `Comparison`. `Comparison.byChange` takes two `Breakdown`s,
`changeIn` takes two `Side`s; the record's only possible job here is to be the source of
the heading "Galicia · 2023 → 2025 · MWh". Building one costs a `Period.pair : Period ->
Period -> Maybe Pair`, because `Pair` is `Years Int Int` and there is no way in from two
`Period` values — and today, with only year controls on screen, that function's `Nothing`
branch cannot be reached. An unreachable branch is exactly what this file refused for
`Reading.Provisional`, for `Period.Granularity`'s `Hourly`/`Daily`, and for `Slot` in the
single-period slice. Adding one to obtain a heading that three fields already in the
model spell out directly would be paying the same price the file has three times refused
to pay.

So the heading is built from `region`, `periodA` and the picked period B. `Comparison`
earns its place when a month control exists: granularity mismatch becomes representable,
`Period.pair`'s `Nothing` becomes reachable, and the record starts guaranteeing something
no group of loose fields does. `Period.at : Slot -> Pair -> Period` waits on the same
commit, for the same reason it did before — no `Pair` exists here, so `Slot` and `Pair`
still never meet.

**Why period B is a `Maybe Period` while period A is not.** The two slots are not
symmetric on screen: A is asked at `init` and always has an answer in flight or in hand,
while B sits unasked until the user picks a year. Giving B a default year and fetching it
at `init` too would buy a symmetric model by asking a question the user did not ask, and
a delta against an arbitrary year is exactly the plausible-looking answer this project
exists not to produce. The cost is that the two periods have different types; `periodFor`
is where they meet.

-}

import Api.Request
import Browser
import Domain.Breakdown as Breakdown exposing (Breakdown, TechnologyReading)
import Domain.Comparison as Comparison exposing (Direction(..), TechnologyDelta)
import Domain.Measure as Measure exposing (Displayable(..), Measure(..), Quantity)
import Domain.Period as Period exposing (Period(..))
import Domain.Reading as Reading exposing (Aggregate(..), Reading(..))
import Domain.Region as Region exposing (Region)
import Domain.RemoteData as RemoteData exposing (Error(..), RemoteData(..))
import Domain.Technology as Technology exposing (Renewability(..))
import Html exposing (Html, button, caption, div, footer, h1, h2, h3, label, option, p, section, select, span, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (class, disabled, scope, selected, value)
import Html.Events exposing (onClick)
import Json.Decode as Decode


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- MODEL


{-| Which of the two periods a message, a request or a field belongs to.

Both variants are constructible, which is precisely what was missing when this file
argued against introducing `Slot` in the single-period slice: `A` is set at `init` and
`B` by its own selector, so neither branch of a `case` over it is dead. That was the
objection — the same one that dropped `Reading.Provisional` and `Period.Granularity`'s
`Hourly`/`Daily` — and it has been answered rather than waived.

`Slot` keys the model rather than being stored in it. The duplication a compiler cannot
police is two record fields of the same type, and `periodFor`/`setPeriod`/`setBreakdown`
confine it to three short `case`s; everything that _does_ something with a slot — fetch,
stale-check, render — is written once and takes the slot as an argument.

Note what the comparison view does **not** do with it: it takes two `Breakdown`s, not two
slots. A slot is which half of the screen asked a question; once both answers are in
hand, the roles that matter are baseline and comparison, and those are carried by the
argument order of `byChange a b`.

-}
type Slot
    = A
    | B


{-| `measure` is one field, not one per slot, for the same reason there is one region
control. §6 compares one region across two periods; the thing being compared has to be
the same thing on both sides, and a per-slot measure would let the screen show MWh in
period A and a percentage in period B with a change column between them — a subtraction
whose two operands have different units. `Quantity` makes that uncomputable in the
domain, and the model should not be able to ask for it either.
-}
type alias Model =
    { region : Region
    , periodA : Period
    , periodB : Maybe Period
    , measure : Measure
    , breakdownA : RemoteData Breakdown
    , breakdownB : RemoteData Breakdown
    }


{-| The question a slot is currently asking, or `Nothing` for a slot nobody has asked
yet — which only `B` can be.

The `Just` around `periodA` is not ceremony: it is the one place where the two slots'
different types have to line up, and lining them up here keeps the `Maybe` out of the
model, where it would claim that A might have no period.

-}
periodFor : Slot -> Model -> Maybe Period
periodFor slot model =
    case slot of
        A ->
            Just model.periodA

        B ->
            model.periodB


setPeriod : Slot -> Period -> Model -> Model
setPeriod slot period model =
    case slot of
        A ->
            { model | periodA = period }

        B ->
            { model | periodB = Just period }


breakdownFor : Slot -> Model -> RemoteData Breakdown
breakdownFor slot model =
    case slot of
        A ->
            model.breakdownA

        B ->
            model.breakdownB


setBreakdown : Slot -> RemoteData Breakdown -> Model -> Model
setBreakdown slot breakdown model =
    case slot of
        A ->
            { model | breakdownA = breakdown }

        B ->
            { model | breakdownB = breakdown }


{-| Every message about one half of the screen carries a `Slot`. `RegionSelected` and
`MeasureToggled` carry none, because neither the region nor the measure belongs to a
slot: §6's comparison is same-region, same-measure, different-period, so there is one
control for each and both apply to the whole screen.

`YearSelected Slot Int` rather than a `YearASelected`/`YearBSelected` pair. Both controls
do the identical thing to different slots; two constructors would make the reader diff
two `update` branches to discover they are the same, and would multiply again the moment
a month control or a third slot appears. The slot is data, so it travels as data.

`Int` rather than `Period` is unchanged from the single-period slice: a year is what the
control can produce, and a `Period` argument would accept a `WholeMonth` that nothing on
screen can build. It widens to `PeriodSelected Slot Period` when a month control exists
to justify it.

`MeasureToggled` carries no `Measure`, although the control that sends it is a pair of
buttons that each know which measure they stand for. With exactly two measures, "select
the other one" and "toggle" are the same operation, and the button that would send
`MeasureSelected Energy` while `Energy` is already showing is disabled — so the payload
would only ever be `Measure.toggle model.measure` recomputed by the view. It becomes
`MeasureSelected Measure` if a third measure ever appears, at which point `Measure.toggle`
stops being well defined too.

-}
type Msg
    = RegionSelected Region
    | YearSelected Slot Int
    | MeasureToggled
    | GotBreakdown Slot (Result Error Breakdown)
    | Retry Slot


{-| `init` asks for period A immediately, so slot A starts at `Loading` and never at
`NotAsked`. Slot B starts at `NotAsked` and stays there until the user picks a year.

The alternative for A is an empty first screen with a "Load" button the PRD never asked
for. `NotAsked` is not thereby unreachable, as it was in the single-period slice: it is
now exactly slot B's opening state, so the view renders it as its own thing instead of
folding it in with `Loading`. "Loading…" over a slot nobody has asked about would be a
lie that never resolves, and a blank would leave the second selector looking broken
rather than unused.

`Energy` is the opening measure because MWh is what the API returns and what the rest of
the screen states its unit as; a share is derived from it. Opening in `Share` would put
a computed figure in front of the reader before the figure it is computed from.

-}
init : () -> ( Model, Cmd Msg )
init _ =
    let
        model =
            { region = Region.default
            , periodA = WholeYear latestCompleteYear
            , periodB = Nothing
            , measure = Energy
            , breakdownA = Loading
            , breakdownB = NotAsked
            }
    in
    ( model, fetch A model.region model.periodA )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        RegionSelected region ->
            { model | region = region }
                |> refresh A
                |> andRefresh B

        YearSelected slot year ->
            model
                |> setPeriod slot (WholeYear year)
                |> refresh slot

        --  No refetch, and that is the payoff of `Measure` being a view concern rather
        --  than a property of the data. One request returns one set of MWh figures;
        --  a share is those figures divided by the `Generación total` row that arrived
        --  in the same response. There is no percentage endpoint to ask for, so asking
        --  again would return byte-identical JSON.
        MeasureToggled ->
            ( { model | measure = Measure.toggle model.measure }, Cmd.none )

        Retry slot ->
            refresh slot model

        --  A response is dropped unless it answers the question **its own slot** is
        --  currently asking.
        --
        --  Not a hypothetical race: a cold upstream miss takes 2–5 s, so switching
        --  Galicia → Ceuta mid-flight otherwise renders Galicia's numbers under Ceuta's
        --  heading. The guard needs no `Msg` payload beyond the slot, because
        --  `Api.Decode` already stamps the requested region and period into the
        --  `Breakdown` — a direct dividend of that decoder taking the request as
        --  arguments.
        --
        --  The period is checked against `periodFor slot`, not against "either slot's
        --  current period", and that is the whole reason the accessor is slot-keyed.
        --  Both slots ask the same API for the same region, so an abandoned A response
        --  is very often a perfectly valid *B* answer: set A to 2019, then set B to 2019
        --  before A's request lands, and a check against either period would file A's
        --  stale response under A as though it were fresh. Two slots on the same year is
        --  a normal thing to pass through on the way to picking the second one, not a
        --  corner case.
        --
        --  It covers successes only. A stale `Error` carries a slot but no period, so it
        --  can no longer land in the wrong half of the screen, but a failure for a year
        --  its slot has since moved off can still surface there. That shows a retryable
        --  error rather than wrong numbers, so the free half covers the harmful half.
        --  Closing the other half means a per-slot request counter carried out in the
        --  request and back in the `Msg`; not taken, because it buys the removal of a
        --  stale error message and costs a piece of state with no other reader.
        GotBreakdown slot (Ok breakdown) ->
            if breakdown.region == model.region && periodFor slot model == Just breakdown.period then
                ( setBreakdown slot (Success breakdown) model, Cmd.none )

            else
                ( model, Cmd.none )

        GotBreakdown slot (Err error) ->
            ( setBreakdown slot (Failure error) model, Cmd.none )


{-| Re-ask one slot's question, if it has one: discard the old answer, because it answers
a question nobody is asking any more, and ask again.

The `Nothing` branch is not a defensive stub. Changing the region refreshes both slots,
and a region change while B is unset must leave B unasked rather than invent a year to
fetch for it — so that branch runs every time someone changes region before picking a
period B. `Retry` never reaches it (the retry button exists only inside a `Failure`,
which a slot can only reach by having been asked), but the sentence is the same either
way: a slot with no question has nothing to re-ask.

-}
refresh : Slot -> Model -> ( Model, Cmd Msg )
refresh slot model =
    case periodFor slot model of
        Nothing ->
            ( model, Cmd.none )

        Just period ->
            ( setBreakdown slot Loading model
            , fetch slot model.region period
            )


{-| Chains a second `refresh` onto the first, for the one trigger that reloads both
slots. Written out here rather than reached for as a general effect-chaining helper,
because there are exactly two slots and exactly one caller.
-}
andRefresh : Slot -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
andRefresh slot ( model, cmd ) =
    let
        ( refreshed, extraCmd ) =
            refresh slot model
    in
    ( refreshed, Cmd.batch [ cmd, extraCmd ] )


{-| `GotBreakdown slot` partially applied is the whole of slot-awareness in the request
path. `Api.Request.breakdown` takes a region and a period and knows nothing about slots,
which is right: the API has no opinion about which half of the screen asked. The slot is
carried by the message constructor and comes back attached to the answer.
-}
fetch : Slot -> Region -> Period -> Cmd Msg
fetch slot region period =
    Api.Request.breakdown region period (GotBreakdown slot)


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- YEARS


{-| The selectable window, newest first.

The **lower** bound is 2010 and is deliberately a year some regions do not have.
Coverage is not uniform: Ceuta and Melilla return data for 2009 and 2010, while Galicia
and Andalucía answer `502` before 2011 (verified against the live API). No single year
list is therefore valid for every region, so trimming the list to the mainland's window
would not remove the 502 — it would only hide that the window is per-region while still
letting a user find the gap. An honest offer plus a legible error beats a list that
quietly claims uniform coverage.

The **upper** bound is the last _complete_ year, because `WholeYear 2026` is a claim the
calendar cannot support yet: the API answers it with a partial year, which would render
under a "2026" heading as though it were twelve months of generation.

Both slots offer the same list, including the year the other slot already holds.
Comparing a period against itself is a pointless question rather than an invalid one —
it produces a table of zero deltas, which is legible — and filtering each list against the
other slot's choice would make the options move under the user's cursor as the other
selector changes.

Known rot, stated rather than hidden: `latestCompleteYear` is a constant, so this list
goes stale each January. The fix is to pass `Date.now()` in as a flag and derive it —
about eight lines, `Program () …` becoming `Program Int …`. Not taken here because it is
outside this slice, not because it is hard.

-}
latestCompleteYear : Int
latestCompleteYear =
    2025


selectableYears : List Int
selectableYears =
    List.range 2010 latestCompleteYear
        |> List.reverse



-- VIEW


{-| **On styling.** Tailwind is applied consistently or not at all; a half-styled table
is worse than either extreme, because the parts that got attention read as the parts that
matter. The vocabulary here is deliberately small and repeated: one page container, one
bordered card per region of the screen, one table style with right-aligned numeric
columns, and one muted style for every sentence that stands in for a missing figure.

Direction is **never** carried by colour. Red-for-down and green-for-up would assert a
value judgement the data does not support — non-renewable generation falling and
renewable generation falling are the same arrow and opposite news — and would put the
only signal in a channel a colour-blind reader cannot use. The arrow and the explicit
sign carry it instead, both of them readable as text.

-}
view : Model -> Html Msg
view model =
    div [ class "mx-auto max-w-5xl space-y-6 p-6 text-slate-800" ]
        [ h1 [ class "text-2xl font-semibold" ]
            [ text "Renewable generation by technology" ]
        , viewControls model
        , viewFigures model
        , viewFootnote model
        ]


viewControls : Model -> Html Msg
viewControls model =
    div [ class "flex flex-wrap items-end gap-6 rounded border border-slate-200 bg-slate-50 p-4" ]
        [ viewRegionControl model.region
        , viewYearControl A (periodFor A model)
        , viewYearControl B (periodFor B model)
        , viewMeasureControl model.measure
        ]


{-| One region control above both slots, because the region is not a property of either
one. §6 compares the same region across two periods, so a per-slot region selector would
offer a comparison the rest of the app cannot express and the domain has no way to label.
-}
viewRegionControl : Region -> Html Msg
viewRegionControl current =
    label [ class "flex flex-col gap-1" ]
        [ span [ class "text-sm font-medium" ] [ text "Region" ]
        , select
            [ onSelect Region.fromGeoIdString RegionSelected
            , class "rounded border border-slate-300 bg-white px-2 py-1.5"
            ]
            (List.map (regionOption current) Region.all)
        ]


{-| The slots are labelled by their role and by their constructor name — "Baseline (A)",
"Compared with (B)".

The single-period slice deferred exactly this rename, on the grounds that "baseline" and
"comparison" would name a role neither slot had while nothing on screen compared them.
They have the roles now: `Comparison.byChange a b` computes B minus A, so A _is_ the
baseline and the direction of every arrow on screen is stated relative to it. Keeping the
bare letter alongside means a bug report saying "B has the wrong year" still names a
variant rather than requiring translation.

The unpicked option appears only while the slot has no period, and is `disabled` so it
cannot be chosen back. There is no route from picked to unpicked, which is deliberate:
"compare against nothing" is where slot B starts, not somewhere §6 asks to return to, and
a control that could empty the comparison would need a `Msg` of its own and a reason for
it.

-}
viewYearControl : Slot -> Maybe Period -> Html Msg
viewYearControl slot current =
    label [ class "flex flex-col gap-1" ]
        [ span [ class "text-sm font-medium" ] [ text (slotLabel slot) ]
        , select
            [ onSelect String.toInt (YearSelected slot)
            , class "rounded border border-slate-300 bg-white px-2 py-1.5"
            ]
            (case current of
                Nothing ->
                    unpickedOption :: List.map (yearOption current) selectableYears

                Just _ ->
                    List.map (yearOption current) selectableYears
            )
        ]


slotLabel : Slot -> String
slotLabel slot =
    case slot of
        A ->
            "Baseline (A)"

        B ->
            "Compared with (B)"


unpickedOption : Html Msg
unpickedOption =
    option [ value "", selected True, disabled True ] [ text "— pick a year —" ]


regionOption : Region -> Region -> Html Msg
regionOption current region =
    option
        [ value (Region.geoIdToString (Region.toGeoId region))
        , selected (region == current)
        ]
        [ text (Region.toName region) ]


yearOption : Maybe Period -> Int -> Html Msg
yearOption current year =
    option
        [ value (String.fromInt year)
        , selected (Just (WholeYear year) == current)
        ]
        [ text (String.fromInt year) ]


{-| Both measures are shown, with the active one marked and `disabled`.

`disabled` here does not mean "unavailable"; it means "already the answer", and it is
what makes `MeasureToggled` correct without a payload — the only clickable button is
always the other one, so a click and a toggle are the same event. A single button reading
"Show as %" would need no disabled state, but it would name only the destination and
leave the reader working out which of the two they are currently looking at from the
figures.

Labels come from `Measure.axisLabel`, so the control and any axis derived from the same
measure cannot drift into two vocabularies. It also means the share button says
"% of total generation" rather than "%", which is the denominator stated on the control
that selects it.

-}
viewMeasureControl : Measure -> Html Msg
viewMeasureControl current =
    div [ class "flex flex-col gap-1" ]
        [ span [ class "text-sm font-medium" ] [ text "Show figures as" ]
        , div [ class "inline-flex overflow-hidden rounded border border-slate-300" ]
            (List.map (measureButton current) [ Energy, Share ])
        ]


measureButton : Measure -> Measure -> Html Msg
measureButton current measure =
    button
        [ onClick MeasureToggled
        , disabled (measure == current)
        , class
            (if measure == current then
                "bg-slate-800 px-3 py-1.5 text-sm font-medium text-white"

             else
                "bg-white px-3 py-1.5 text-sm text-slate-700 hover:bg-slate-100"
            )
        ]
        [ text (Measure.axisLabel measure) ]



-- FIGURES


{-| Two `Success`es make a comparison; anything else falls back to whatever each slot has
on its own.

The fork here was whether a lone period A should show its own figures or whether the
comparison area should just hold the "Pick a year to compare against." invitation until
both slots land. Showing each slot's own table, because the standing guarantee is that
one slot failing never blanks the other, and an invitation-only fallback would honour it
in the model and break it on screen: B failing with A loaded would leave a page with no
generation figures on it at all, despite the app holding a full breakdown for A.

So the fallback is symmetric and per-slot — each half renders its own `RemoteData`,
including its own retry button — and the comparison replaces both halves only when there
is genuinely something to compare. The single-period table is subsumed rather than
duplicated: the comparison shows the same per-technology figures in its first two
columns.

-}
viewFigures : Model -> Html Msg
viewFigures model =
    case ( model.breakdownA, model.breakdownB ) of
        ( Success a, Success b ) ->
            viewComparison model.measure a b

        _ ->
            div [ class "grid gap-6 md:grid-cols-2" ]
                [ viewSlotPanel A model
                , viewSlotPanel B model
                ]


viewSlotPanel : Slot -> Model -> Html Msg
viewSlotPanel slot model =
    section [ class "space-y-3 rounded border border-slate-200 p-4" ]
        [ h2 [ class "text-lg font-medium" ]
            [ text (slotLabel slot ++ panelPeriod (periodFor slot model)) ]
        , case breakdownFor slot model of
            NotAsked ->
                p [ class "text-slate-600" ] [ text "Pick a year to compare against." ]

            Loading ->
                p [ class "text-slate-600" ] [ text "Loading…" ]

            Failure error ->
                viewError slot error

            Success breakdown ->
                viewSinglePeriod model.measure breakdown
        ]


panelPeriod : Maybe Period -> String
panelPeriod period =
    case period of
        Nothing ->
            ""

        Just picked ->
            " · " ++ Period.label picked


{-| One period's own figures, for the halves of the screen where there is no second
period to subtract.

Rows keep the order REData returned them in, rather than being sorted by size. There is
no "what moved" to sort by here — that ordering is `byChange`'s whole argument and it
needs two periods — and REData's order is stable across regions and years, so the rows
do not rearrange themselves when the user changes the year of a slot that is already on
screen.

-}
viewSinglePeriod : Measure -> Breakdown -> Html Msg
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


headlineRow : Measure -> Breakdown -> Renewability -> Html Msg
headlineRow measure breakdown renewability =
    tr [ class "border-b border-slate-100" ]
        [ rowHeading (renewabilityLabel renewability) Nothing
        , td [ class "py-1.5 text-right" ]
            [ viewAggregate measure breakdown renewability ]
        ]


singlePeriodRow : Measure -> Breakdown -> TechnologyReading -> Html Msg
singlePeriodRow measure breakdown technologyReading =
    tr [ class "border-b border-slate-100" ]
        [ rowHeading
            (Technology.toName technologyReading.technology)
            (Just (renewabilityLabel technologyReading.renewability))
        , td [ class "py-1.5 text-right" ]
            [ viewDisplayable (Measure.display measure breakdown.total technologyReading.reading) ]
        ]



-- COMPARISON


viewComparison : Measure -> Breakdown -> Breakdown -> Html Msg
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


viewHeadlines : Measure -> Breakdown -> Breakdown -> Html Msg
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


headlineComparisonRow : Measure -> Breakdown -> Breakdown -> Renewability -> Html Msg
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
viewAggregate : Measure -> Breakdown -> Renewability -> Html Msg
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
viewHeadlineChange : Measure -> Breakdown -> Breakdown -> Renewability -> Html Msg
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
viewRelativeChange : Measure -> Reading -> Reading -> Html Msg
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


viewTechnologyTable : Measure -> Breakdown -> Breakdown -> Html Msg
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


technologyRow : Measure -> Breakdown -> Breakdown -> TechnologyDelta -> Html Msg
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
viewChange : Measure -> Breakdown -> Breakdown -> TechnologyDelta -> Html Msg
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



-- RENDERING VALUES


{-| The three outcomes of asking for a figure, each with its own words.

`NoMeasurement` and `ShareUndefined` must not read alike — they are different facts, and
`Domain.Measure` keeps them apart in the type precisely so that a view cannot flatten
them. "not measured" is about the technology; "share undefined" is about the denominator,
and it appears only in share mode, where a region with no recorded generation at all
would otherwise show 0% for everything.

Neither is a dash. A dash in a numeric column is read as a zero by anyone scanning it,
which is the single failure this whole model is built to avoid.

-}
viewDisplayable : Displayable -> Html msg
viewDisplayable displayable =
    case displayable of
        Shown quantity ->
            span [ class "tabular-nums" ] [ text (formatQuantity quantity) ]

        NoMeasurement ->
            gap "not measured"

        ShareUndefined ->
            gap "share undefined"


gap : String -> Html msg
gap wording =
    span [ class "text-xs italic text-slate-500" ] [ text wording ]


{-| A change, with its direction stated twice: once as an arrow and once as the sign.

The redundancy is deliberate. The arrow is what a reader scanning the column sees, the
sign is what survives being read aloud or copied out of the page, and neither is a
colour.

**The direction is taken from the rounded figure, not from the raw one**, and that is
the whole reason `roundTo` exists. Galicia 2025 → 2023 in share mode found it
immediately: Residuos renovables moves by about a fiftieth of a percentage point, which
`Comparison.direction` calls `Down` and one decimal place prints as `0.0`. The cell read
"▼ 0.0 pp" — an arrow asserting a fall next to a number asserting none, with the sign
dropped because `signed` only marks increases. A reader cannot act on either half of
that, and cannot tell which half to believe.

Rounding first makes the arrow and the digits agree by construction. The cost is that a
movement smaller than the printed precision is reported as `Flat`, which is why `Flat`
does not say "no change": it says "no change at this precision", which is true both of an
exact zero and of a change too small to print.

-}
viewSignedQuantity : Quantity -> Html msg
viewSignedQuantity quantity =
    span [ class "tabular-nums" ]
        [ text
            (case Comparison.direction (roundTo (decimalsFor quantity) (Measure.amount quantity)) of
                Up ->
                    "▲ " ++ formatSignedQuantity quantity

                Down ->
                    "▼ " ++ formatSignedQuantity quantity

                Flat ->
                    "no change at this precision"
            )
        ]


{-| Number and unit, always together. `Measure.amount` and `Measure.unitLabel` take the
same `Quantity`, so this is the one function where the two could be separated and it is
the one function that never separates them.

MWh get one decimal place below a thousand and none above it. Regional figures span six
orders of magnitude — Ceuta reports tens of MWh where Galicia reports millions — so a
fixed precision is either noise at the top or a lie at the bottom, and "12" for 12.3 MWh
in Ceuta is a lie the reader has no way to detect. Percentages and percentage points get
one decimal at every size, since they are bounded.

-}
formatQuantity : Quantity -> String
formatQuantity quantity =
    fixed (decimalsFor quantity) (Measure.amount quantity)
        ++ " "
        ++ Measure.unitLabel quantity


formatSignedQuantity : Quantity -> String
formatSignedQuantity quantity =
    signed (decimalsFor quantity) (Measure.amount quantity)
        ++ " "
        ++ Measure.unitLabel quantity


decimalsFor : Quantity -> Int
decimalsFor quantity =
    if abs (Measure.amount quantity) >= 1000 then
        0

    else
        1


{-| Fixed decimal places with grouped thousands, written out because Elm's
`String.fromFloat` drops trailing zeros and groups nothing: 1234567.0 becomes
"1234567" and 25.0 becomes "25", which puts three different column widths in one column.

Rounding happens once, on the scaled integer, and the sign is taken from the **rounded**
value rather than the original — otherwise -0.04 at one decimal place renders as "-0.0",
a negative zero that suggests a decline that did not happen.

-}
fixed : Int -> Float -> String
fixed decimals value =
    let
        scaled =
            round (abs value * toFloat (10 ^ decimals))

        digits =
            String.padLeft (decimals + 1) '0' (String.fromInt scaled)

        sign =
            if scaled /= 0 && value < 0 then
                "-"

            else
                ""

        fraction =
            if decimals == 0 then
                ""

            else
                "." ++ String.right decimals digits
    in
    sign ++ groupThousands (String.dropRight decimals digits) ++ fraction


{-| Same, with an explicit `+` on increases, for cells whose whole content is a change.

The sign is decided on the rounded value for the reason `viewSignedQuantity` gives: a
`+` in front of a printed `0.0` is the same contradiction as an arrow in front of one.

-}
signed : Int -> Float -> String
signed decimals value =
    case Comparison.direction (roundTo decimals value) of
        Up ->
            "+" ++ fixed decimals value

        _ ->
            fixed decimals value


{-| The value as `fixed` will actually print it.

Deliberately reproduces `fixed`'s rounding step rather than approximating it — magnitude
first, sign reattached after — because the two must agree at a tie. `round` in Elm is
`Math.round`, which breaks ties towards positive infinity, so rounding `-0.05` directly
gives `0` while rounding its magnitude gives `0.1`: the sign function and the digit
function would disagree on exactly the values where agreement is the point.

-}
roundTo : Int -> Float -> Float
roundTo decimals value =
    let
        scale =
            toFloat (10 ^ decimals)

        magnitude =
            toFloat (round (abs value * scale)) / scale
    in
    if value < 0 then
        -magnitude

    else
        magnitude


groupThousands : String -> String
groupThousands digits =
    if String.length digits <= 3 then
        digits

    else
        groupThousands (String.dropRight 3 digits) ++ "," ++ String.right 3 digits


renewabilityLabel : Renewability -> String
renewabilityLabel renewability =
    if Technology.isRenewable renewability then
        "Renewable"

    else
        "Non-renewable"



-- TABLE FURNITURE


columnHeading : String -> Html msg
columnHeading title =
    th [ scope "col", class "py-1.5 text-left font-medium text-slate-600" ] [ text title ]


numericColumnHeading : String -> Html msg
numericColumnHeading title =
    th [ scope "col", class "py-1.5 text-right font-medium text-slate-600" ] [ text title ]


{-| A row's label is a `th`, not a `td`. The comparison tables have headers on two axes
and a screen reader announces a cell by both of them; a row of four numbers whose first
cell is a `td` is announced without ever naming the technology it belongs to.
-}
rowHeading : String -> Maybe String -> Html msg
rowHeading title subtitle =
    th [ scope "row", class "py-1.5 text-left font-normal" ]
        [ text title
        , case subtitle of
            Nothing ->
                text ""

            Just note ->
                span [ class "block text-xs text-slate-500" ] [ text note ]
        ]



-- FOOTNOTE


{-| `lastUpdate` is a footnote, not a per-slot fact.

It is REData's timestamp for the aggregation it published, not a property of the
generation figures beside it, and it is **identical across regions**: verified live, a
2025 request for Andalucía, Galicia and Ceuta all answer
`2026-05-11T21:41:15.000+02:00`. Printing it under each slot's numbers — which is what
the placeholder line this replaces did — states provenance twice and dresses it up as
something the numbers say.

It is **not** constant across periods, which the same check falsified: every region's
2023 request answers `2025-01-28T15:08:07.000+01:00`, a year and a half earlier. So two
slots routinely hold two different stamps, and the footnote names the period each one
belongs to whenever they differ. Deduplicating first means the common case — both slots
on the same publication run — still reads as one sentence about one dataset, and picking
just one stamp is never on the table: it would assert a freshness the other response
directly contradicts.

The string is REData's own and is printed unchanged. We never parsed it into a
`Time.Posix`, so reformatting it would mean inventing a timezone interpretation this app
has not done.

-}
viewFootnote : Model -> Html Msg
viewFootnote model =
    case stampsIn model of
        [] ->
            text ""

        stamps ->
            footer [ class "border-t border-slate-200 pt-3 text-xs text-slate-500" ]
                [ text
                    ("Source: REData (Red Eléctrica de España). Dataset last updated "
                        ++ String.join ", " (List.map (stampSentence stamps) stamps)
                        ++ ". Figures are MWh as published; REData carries no units field, so the unit is asserted from its documentation."
                    )
                ]


{-| One entry per distinct timestamp, carrying the periods that reported it. Distinct
_by timestamp_ rather than by slot, because two slots agreeing is the normal case and the
footnote should not say the same date twice to report it.
-}
stampsIn : Model -> List { lastUpdate : String, periods : List Period }
stampsIn model =
    [ model.breakdownA, model.breakdownB ]
        |> List.filterMap RemoteData.toMaybe
        |> List.foldl
            (\breakdown acc ->
                case List.filter (\entry -> entry.lastUpdate == breakdown.lastUpdate) acc of
                    [] ->
                        acc ++ [ { lastUpdate = breakdown.lastUpdate, periods = [ breakdown.period ] } ]

                    _ ->
                        List.map
                            (\entry ->
                                if entry.lastUpdate == breakdown.lastUpdate then
                                    { entry | periods = entry.periods ++ [ breakdown.period ] }

                                else
                                    entry
                            )
                            acc
            )
            []


{-| The period names are attached only when there is more than one stamp to tell apart.
With a single stamp they would answer a question nobody asked — the reader can see which
periods are on screen — and would make the common case read as though the two slots
disagreed.
-}
stampSentence : List { lastUpdate : String, periods : List Period } -> { lastUpdate : String, periods : List Period } -> String
stampSentence all entry =
    if List.length all <= 1 then
        entry.lastUpdate

    else
        entry.lastUpdate
            ++ " (for "
            ++ String.join " and " (List.map Period.label entry.periods)
            ++ ")"



-- BOUNDARY


{-| Parses the DOM's string at the boundary and sends **no message at all** if it does
not parse, rather than sending a `Maybe` inward for `update` to deal with.

Same move as `Api.Decode`, one layer out: a failing `Json.Decode` handler dispatches
nothing, so `Msg` carries `Region`, not `Maybe Region`, and no branch downstream exists
for a value the DOM should never have produced. The alternative —
`RegionSelected (Maybe Region)` — would put an unreachable case in `update` forever to
describe a `<select>` returning an option it was never given. It covers the unpicked
option's empty value for free as well: `String.toInt ""` is `Nothing`, so a browser that
let a `disabled` option be re-selected would produce no message rather than year 0.

-}
onSelect : (String -> Maybe a) -> (a -> msg) -> Html.Attribute msg
onSelect parse toMsg =
    Html.Events.on "change"
        (Html.Events.targetValue
            |> Decode.andThen
                (\raw ->
                    case parse raw of
                        Just parsed ->
                            Decode.succeed (toMsg parsed)

                        Nothing ->
                            Decode.fail ("Unrecognised option value: " ++ raw)
                )
        )



-- ERRORS


{-| The three failure kinds are named, not just phrased differently.

§6 requires a network failure, a decode failure and an upstream 4xx/5xx to be
distinguishable. `RemoteData.errorMessage` already differs per variant, but the
difference is carried entirely in prose, which asks the reader to infer the category
from the sentence. The heading states the category outright and the sentence says what
to do about it.

The heading is an `h3` beneath the slot's `h2`, because a failure belongs to one slot and
heading level is how that containment is stated to a screen reader — the message text
itself names neither slot.

`errorHeading` lives here rather than beside `errorMessage` because it is a view label
with no counterpart in the domain — the domain's interest in an `Error` is what it means,
not what to title it.

-}
viewError : Slot -> Error -> Html Msg
viewError slot error =
    div [ class "space-y-2 rounded border border-slate-300 bg-slate-50 p-3" ]
        [ h3 [ class "font-medium" ] [ text (errorHeading error) ]
        , p [ class "text-sm" ] [ text (RemoteData.errorMessage error) ]
        , p [ class "text-xs text-slate-500" ] [ text (errorDetail error) ]
        , button
            [ onClick (Retry slot)
            , class "rounded border border-slate-300 bg-white px-3 py-1.5 text-sm hover:bg-slate-100"
            ]
            [ text "Retry" ]
        ]


errorHeading : Error -> String
errorHeading error =
    case error of
        NetworkError ->
            "Network error"

        UpstreamError _ ->
            "Upstream error"

        DecodeError _ ->
            "Unexpected response"


{-| The machine-readable half, kept out of `errorMessage`'s sentence so the sentence
stays readable. A status code is the thing worth quoting back for an upstream failure,
and the decoder's own path is the thing worth quoting for a decode failure.
-}
errorDetail : Error -> String
errorDetail error =
    case error of
        NetworkError ->
            "The request did not reach the proxy."

        UpstreamError status ->
            "REData responded HTTP " ++ String.fromInt status ++ "."

        DecodeError details ->
            details
