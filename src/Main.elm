module Main exposing (main)

import Browser
import Html exposing (Html, div, h1, p, text)
import Html.Attributes exposing (class)


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


type alias Model =
    {}


type Msg
    = NoOp


init : () -> ( Model, Cmd Msg )
init _ =
    ( {}, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Model -> Html Msg
view _ =
    div [ class "min-h-screen bg-slate-50 text-slate-900" ]
        [ div [ class "mx-auto max-w-2xl px-6 py-16" ]
            [ h1 [ class "text-2xl font-semibold tracking-tight" ]
                [ text "renewable-analyzer" ]
            , p [ class "mt-3 text-sm text-slate-600" ]
                [ text "Skeleton only." ]
            ]
        ]
