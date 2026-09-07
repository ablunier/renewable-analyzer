module Main exposing (main)

{-| One region, two periods, two independent requests.

The user picks a region, a year for period A, and a year for period B. Each slot's
answer is its own `RemoteData`, so one period failing to load leaves the other on
screen — the shape `Domain.Comparison`'s doc comment already describes as "two
`Breakdown`s, held separately in the model as independent `RemoteData`". The comparison
between them is not here yet, and the model's shape is still provisional because of it.

**Why `Model` still holds loose fields rather than a `Comparison`.** The reason given in
the single-period slice was that `Comparison.periods` is a `Period.Pair` and a `Pair`
has no one-period inhabitant — and that this would stop being true in the commit that
adds the second selector. Half of it did stop being true: a `Pair` is constructible the
moment the user picks B. The other half did not. A `Comparison` also carries
`measure : Measure`, and no measure control exists, so putting `Energy` in the model
would be the same invention this file rejected for `Years 2025 2025` — a field of the
question that the user was never asked. And B is optional (below), so the model would
hold a `Maybe Comparison`, which would take the region down with it: the region is
shared, always set, and needed to render its control whether or not B has been picked.
`Comparison` arrives with the measure toggle and the view that consumes it, which is the
commit where both objections lift.

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
import Domain.Breakdown exposing (Breakdown)
import Domain.Period as Period exposing (Period(..))
import Domain.Region as Region exposing (Region)
import Domain.RemoteData as RemoteData exposing (Error(..), RemoteData(..))
import Html exposing (Html, button, div, h1, h2, h3, label, option, p, section, select, span, text)
import Html.Attributes exposing (class, disabled, selected, value)
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

Not pushed down into `Domain.Period` as `Period.at : Slot -> Pair -> Period` replacing
`first`/`second`, although that folding is now available in principle. No `Period.Pair`
is in the model (period B is a `Maybe Period`), so `Slot` and `Pair` never meet here, and
moving `Slot` into the domain today would place a UI-shaped type there with no domain
caller. It is worth revisiting in the commit that introduces `Comparison`, where a `Pair`
and a `Slot` are in scope at the same time.

-}
type Slot
    = A
    | B


type alias Model =
    { region : Region
    , periodA : Period
    , periodB : Maybe Period
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


{-| Every message but `RegionSelected` carries a `Slot`, because every one of them is
about one half of the screen. `RegionSelected` carries none because the region is
shared: §6's comparison is same-region, different-period, so there is one region control
and changing it reloads both slots.

`YearSelected Slot Int` rather than a `YearASelected`/`YearBSelected` pair. Both controls
do the identical thing to different slots; two constructors would make the reader diff
two `update` branches to discover they are the same, and would multiply again the moment
a month control or a third slot appears. The slot is data, so it travels as data.

`Int` rather than `Period` is unchanged from the single-period slice: a year is what the
control can produce, and a `Period` argument would accept a `WholeMonth` that nothing on
screen can build. It widens to `PeriodSelected Slot Period` when a month control exists
to justify it.

-}
type Msg
    = RegionSelected Region
    | YearSelected Slot Int
    | GotBreakdown Slot (Result Error Breakdown)
    | Retry Slot


{-| `init` asks for period A immediately, so slot A starts at `Loading` and never at
`NotAsked`. Slot B starts at `NotAsked` and stays there until the user picks a year.

The alternative for A is an empty first screen with a "Load" button the PRD never asked
for. `NotAsked` is not thereby unreachable, as it was in the single-period slice: it is
now exactly slot B's opening state, so `viewBreakdown` renders it as its own thing
instead of folding it in with `Loading`. "Loading…" over a slot nobody has asked about
would be a lie that never resolves, and a blank would leave the second selector looking
broken rather than unused.

-}
init : () -> ( Model, Cmd Msg )
init _ =
    let
        model =
            { region = Region.default
            , periodA = WholeYear latestCompleteYear
            , periodB = Nothing
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
it produces a row of zero deltas, which is legible — and filtering each list against the
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


view : Model -> Html Msg
view model =
    div []
        [ h1 [] [ text "Renewable generation by technology" ]
        , viewRegionControl model.region
        , viewSlot A model
        , viewSlot B model
        ]


{-| One region control above both slots, because the region is not a property of either
one. §6 compares the same region across two periods, so a per-slot region selector would
offer a comparison the rest of the app cannot express and the domain has no way to label.
-}
viewRegionControl : Region -> Html Msg
viewRegionControl current =
    div []
        [ label []
            [ text "Region "
            , select [ onSelect Region.fromGeoIdString RegionSelected ]
                (List.map (regionOption current) Region.all)
            ]
        ]


{-| The slots are headed "Period A" and "Period B", matching the constructor names
exactly, so that a bug report saying "B has the wrong year" names a variant rather than
requiring translation.

"Baseline" and "Comparison" were the alternative and would mean more to a first-time
reader — but they name a role neither slot has yet, since nothing on screen compares them
and B minus A is not computed anywhere in this commit. Renaming them is the comparison
view's business, once the labels would describe something the app actually does.

-}
viewSlot : Slot -> Model -> Html Msg
viewSlot slot model =
    section []
        [ h2 [] [ text ("Period " ++ slotLabel slot) ]
        , viewYearControl slot (periodFor slot model)
        , viewBreakdown slot (breakdownFor slot model)
        ]


slotLabel : Slot -> String
slotLabel slot =
    case slot of
        A ->
            "A"

        B ->
            "B"


{-| The unpicked option appears only while the slot has no period, and is `disabled` so
it cannot be chosen back. There is no route from picked to unpicked, which is deliberate:
"compare against nothing" is where slot B starts, not somewhere §6 asks to return to, and
a control that could empty the comparison would need a `Msg` of its own and a reason for
it.
-}
viewYearControl : Slot -> Maybe Period -> Html Msg
viewYearControl slot current =
    label []
        [ text "Year "
        , select [ onSelect String.toInt (YearSelected slot) ]
            (case current of
                Nothing ->
                    unpickedOption :: List.map (yearOption current) selectableYears

                Just _ ->
                    List.map (yearOption current) selectableYears
            )
        ]


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


{-| `NotAsked` renders as an invitation rather than as "Loading…", now that it is a state
the app can actually be in — see `init`. It is the only one of the four that describes
the user's turn rather than the network's.

`Success` still echoes the decoded period instead of the readings, which is the same
placeholder the single-period slice had; the technology table is the comparison view's
work. The period is worth echoing in the meantime because it is the visible proof that
each slot's numbers answer that slot's question.

-}
viewBreakdown : Slot -> RemoteData Breakdown -> Html Msg
viewBreakdown slot data =
    case data of
        NotAsked ->
            p [] [ text "Pick a year to compare against." ]

        Loading ->
            p [] [ text "Loading…" ]

        Failure error ->
            viewError slot error

        Success breakdown ->
            p []
                [ text
                    (Period.label breakdown.period
                        ++ " decoded, last updated "
                        ++ breakdown.lastUpdate
                    )
                ]


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
    div []
        [ h3 [] [ text (errorHeading error) ]
        , p [] [ text (RemoteData.errorMessage error) ]
        , p [] [ span [ class "text-sm" ] [ text (errorDetail error) ] ]
        , button [ onClick (Retry slot) ] [ text "Retry" ]
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
