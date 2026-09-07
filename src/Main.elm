module Main exposing (main)

{-| One region, one period, one request.

This is the vertical slice: the controls the user actually has, the request they
trigger, and the four states the answer can be in. The two-period comparison is not
here yet, and two of this module's shapes are deliberately provisional because of it.

**Why `Model` holds loose fields rather than a `Comparison`.** `Domain.Comparison` is
the right home for "what the user asked" — but its `periods` field is a `Period.Pair`,
and a `Pair` has no one-period inhabitant. Holding a `Comparison` today would mean
constructing `Years 2025 2025`: a comparison of a year against itself, carrying a
second period no control can set. `Comparison`'s own doc comment calls it "the question,
not the answer", and that is precisely the argument against using it here — the question
the user can currently ask has one period in it, so a `Comparison` would misstate it.
It arrives in the same commit as the second period selector, which is when it becomes
true.

**Why one `breakdown` field rather than a slot-keyed pair.** The destination is
`type Slot = A | B` with `GotBreakdown Slot (Result …)`, one `fetch` and one `update`
branch instead of two copy-paste ones — a duplication the compiler cannot police, since
both fields would have the same type. That slot is not built yet because only one of its
two variants would be constructible, and a variant nothing can reach is a dead branch in
every `case` over it. This codebase has refused that twice already on the same grounds:
`Reading.Provisional` was dropped because no response produces it, and
`Period.Granularity` omits `Hourly`/`Daily` because CCAA level cannot return them.
Introducing a dead `B` here would contradict the precedent.

-}

import Api.Request
import Browser
import Domain.Breakdown exposing (Breakdown)
import Domain.Period exposing (Period(..))
import Domain.Region as Region exposing (Region)
import Domain.RemoteData as RemoteData exposing (Error(..), RemoteData(..))
import Html exposing (Html, button, div, h1, h2, label, option, p, select, span, text)
import Html.Attributes exposing (class, selected, value)
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


type alias Model =
    { region : Region
    , period : Period
    , breakdown : RemoteData Breakdown
    }


{-| `YearSelected Int` rather than `PeriodSelected Period`, because a year is what the
control can produce. A `Period` argument would accept a `WholeMonth` that nothing on
screen can build, which is the same dead-path objection as the slot above. It widens to
`PeriodSelected Period` when a month control exists to justify it.
-}
type Msg
    = RegionSelected Region
    | YearSelected Int
    | GotBreakdown (Result Error Breakdown)
    | Retry


{-| `init` asks immediately, so the model starts at `Loading` and never at `NotAsked`.

The alternative is an empty first screen with a "Load" button the PRD never asked for.
The cost is that `NotAsked` is unreachable in this slice — so `viewBreakdown` folds it in
with `Loading` rather than pretending it is a distinct thing to render. It stops being
unreachable in the next commit: period A is fetched at init, while period B sits unasked
until the user picks one, which is exactly the state the variant exists for.

-}
init : () -> ( Model, Cmd Msg )
init _ =
    let
        model =
            { region = Region.default
            , period = WholeYear latestCompleteYear
            , breakdown = Loading
            }
    in
    ( model, fetch model.region model.period )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        RegionSelected region ->
            reload { model | region = region }

        YearSelected year ->
            reload { model | period = WholeYear year }

        Retry ->
            reload model

        --  A response is dropped unless it answers the question currently on screen.
        --  Not a hypothetical race: a cold upstream miss takes 2–5 s, so switching
        --  Galicia → Ceuta mid-flight otherwise renders Galicia's numbers under Ceuta's
        --  heading. The guard needs no extra `Msg` payload because `Api.Decode` already
        --  stamps the requested region and period into the `Breakdown` — a direct
        --  dividend of that decoder taking the request as arguments.
        --
        --  It covers successes only. A stale `Error` carries no identity, so a failure
        --  for an abandoned request can still surface — but that shows a retryable error
        --  rather than wrong numbers, so the free half covers the harmful half. Request
        --  identity gets modelled properly when `Slot` lands.
        GotBreakdown (Ok breakdown) ->
            if breakdown.region == model.region && breakdown.period == model.period then
                ( { model | breakdown = Success breakdown }, Cmd.none )

            else
                ( model, Cmd.none )

        GotBreakdown (Err error) ->
            ( { model | breakdown = Failure error }, Cmd.none )


{-| Every one of the three triggers does the same thing: discard the old answer, because
it answers a question nobody is asking any more, and ask again.
-}
reload : Model -> ( Model, Cmd Msg )
reload model =
    ( { model | breakdown = Loading }, fetch model.region model.period )


fetch : Region -> Period -> Cmd Msg
fetch region period =
    Api.Request.breakdown region period GotBreakdown


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
        , viewControls model
        , viewBreakdown model.breakdown
        ]


viewControls : Model -> Html Msg
viewControls model =
    div []
        [ label []
            [ text "Region "
            , select [ onSelect Region.fromGeoIdString RegionSelected ]
                (List.map (regionOption model.region) Region.all)
            ]
        , text " "
        , label []
            [ text "Year "
            , select [ onSelect String.toInt YearSelected ]
                (List.map (yearOption model.period) selectableYears)
            ]
        ]


regionOption : Region -> Region -> Html Msg
regionOption current region =
    option
        [ value (Region.geoIdToString (Region.toGeoId region))
        , selected (region == current)
        ]
        [ text (Region.toName region) ]


yearOption : Period -> Int -> Html Msg
yearOption current year =
    option
        [ value (String.fromInt year)
        , selected (WholeYear year == current)
        ]
        [ text (String.fromInt year) ]


{-| Parses the DOM's string at the boundary and sends **no message at all** if it does
not parse, rather than sending a `Maybe` inward for `update` to deal with.

Same move as `Api.Decode`, one layer out: a failing `Json.Decode` handler dispatches
nothing, so `Msg` carries `Region`, not `Maybe Region`, and no branch downstream exists
for a value the DOM should never have produced. The alternative —
`RegionSelected (Maybe Region)` — would put an unreachable case in `update` forever to
describe a `<select>` returning an option it was never given.

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


viewBreakdown : RemoteData Breakdown -> Html Msg
viewBreakdown data =
    case data of
        --  Folded together on purpose: `init` asks, so `NotAsked` cannot occur here.
        --  Giving it its own rendering would be describing a state this app has no way
        --  to enter. See `init`.
        NotAsked ->
            p [] [ text "Loading…" ]

        Loading ->
            p [] [ text "Loading…" ]

        Failure error ->
            viewError error

        Success breakdown ->
            p [] [ text ("Decoded, last updated " ++ breakdown.lastUpdate) ]


{-| The three failure kinds are named, not just phrased differently.

§6 requires a network failure, a decode failure and an upstream 4xx/5xx to be
distinguishable. `RemoteData.errorMessage` already differs per variant, but the
difference is carried entirely in prose, which asks the reader to infer the category
from the sentence. The heading states the category outright and the sentence says what
to do about it.

`errorHeading` lives here rather than beside `errorMessage` because it is a view label
with no counterpart in the domain — the domain's interest in an `Error` is what it means,
not what to title it.

-}
viewError : Error -> Html Msg
viewError error =
    div []
        [ h2 [] [ text (errorHeading error) ]
        , p [] [ text (RemoteData.errorMessage error) ]
        , p [] [ span [ class "text-sm" ] [ text (errorDetail error) ] ]
        , button [ onClick Retry ] [ text "Retry" ]
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
