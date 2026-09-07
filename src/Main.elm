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

**What is left here.** This file holds the state, the messages, the effects, and the
controls that produce them — everything whose type mentions `Model` or `Msg`. The tables
of numbers do not: they are `Html msg`, functions of `Domain` values alone, and they live
in `View.Figures` and `View.Value`. That is the line the split follows, and it is the
only line worth following in Elm, where the module graph has to be acyclic. Splitting by
layer instead — a `Model.elm`, an `Update.elm`, a `View.elm` — forces `Msg` out into a
types module that every layer imports and nothing owns, and leaves each file still
depending on the whole `Model`. Splitting by _what the code needs to know_ cost nothing
here, because the twelve functions that moved already needed nothing.

`viewFigures` and `viewSlotPanel` stay because they read `RemoteData` and can emit
`Retry`: they decide **whether** there is a comparison to draw. `View.Figures` draws it.

-}

import Api.Request
import Browser
import Domain.Breakdown exposing (Breakdown)
import Domain.Measure as Measure exposing (Measure(..))
import Domain.Period as Period exposing (Period(..))
import Domain.Region as Region exposing (Region)
import Domain.RemoteData as RemoteData exposing (Error(..), RemoteData(..))
import Html exposing (Html, button, div, footer, h1, h2, h3, label, option, p, section, select, span, text)
import Html.Attributes exposing (class, disabled, selected, value)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import View.Figures exposing (viewComparison, viewSinglePeriod)


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
            , periodA = WholeYear Period.latestCompleteYear
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

Both slots offer the same list — `Period.selectableYears`, which argues its own bounds —
including the year the other slot already holds. Comparing a period against itself is a
pointless question rather than an invalid one, since it produces a table of zero deltas
and reads perfectly well, and filtering each list against the other slot's choice would
make the options move under the user's cursor as the other selector changes.

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
                    unpickedOption :: List.map (yearOption current) Period.selectableYears

                Just _ ->
                    List.map (yearOption current) Period.selectableYears
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
