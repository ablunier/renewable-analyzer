module Api.Request exposing (breakdown, interpretResponse, url)

{-| The one request this application makes, and the mapping from HTTP outcome to
`Domain.RemoteData.Error`.

The widget, category and language are fixed rather than parameters. Being a
general-purpose REData browser is an explicit non-goal: this asks
`generacion/estructura-generacion` in Spanish and nothing else, and the proxy's
allowlist encodes the same restriction on the other side. Making them arguments would
invent a generality neither end supports.

-}

import Api.Decode
import Domain.Breakdown exposing (Breakdown)
import Domain.Period as Period exposing (Period)
import Domain.Region as Region exposing (Region)
import Domain.RemoteData exposing (Error(..))
import Http
import Json.Decode exposing (Decoder)
import Url.Builder


breakdown : Region -> Period -> (Result Error Breakdown -> msg) -> Cmd msg
breakdown region period toMsg =
    Http.get
        { url = url region period
        , expect =
            Http.expectStringResponse toMsg
                (interpretResponse (Api.Decode.breakdown region period))
        }


{-| A **relative** URL, built rather than concatenated.

Relative because the app and the proxy are one origin: `/api/...` resolves to Vite's
dev-server proxy on :8000 in development and to `server/main.ts` itself in production,
with no environment switch and no base-URL configuration to get wrong.

`Url.Builder` rather than `++`, because query values here contain characters that need
encoding — `start_date` is `2018-01-01T00:00`, and the `:` becomes `%3A`. Hand-rolled
query strings work until the first value that needs escaping, and then fail somewhere
downstream rather than here.

**`geo_trunc` is deliberately absent.** REE's own documented example sends
`geo_trunc=electric_system` alongside `geo_limit=ccaa`, mixing the two geographic axes.
What `geo_trunc` controls in that combination was never established, so this app stays
on one axis. `geo_limit` is the constant `"ccaa"` for all 19 regions, which is why
`Region.geoLimit` is a module-level constant and not a function of the region.

-}
url : Region -> Period -> String
url region period =
    Url.Builder.absolute
        [ "api", "es", "datos", "generacion", "estructura-generacion" ]
        [ Url.Builder.string "start_date" (Period.startDate period)
        , Url.Builder.string "end_date" (Period.endDate period)
        , Url.Builder.string "time_trunc"
            (Period.timeTrunc (Period.granularityOf period))
        , Url.Builder.string "geo_limit" Region.geoLimit
        , Url.Builder.string "geo_ids"
            (Region.geoIdToString (Region.toGeoId region))
        ]


{-| Status code in, `Error` out — the body of a failure is never read.

`Http.expectStringResponse` rather than `Http.expectJson`. Both can produce the right
answer; `expectJson` would give `BadStatus 500` for the HTML Symfony error page without
choking on it. The reason to write the dispatch out by hand is that the rule being
followed is a stated requirement and not an obvious one, and here it is visible: the
`BadStatus_` branch binds the body to `_`. Error bodies from REData are **not
consistently JSON** — a 400 and a 502 return `{"errors":[...]}`, while `time_trunc=day`
at CCAA level returns an HTML page — so any code that reached for the body would have
to guess which. It never guesses, because it never looks.

It also makes this a pure function over a value a test can construct, which is how the
HTML-body case is tested without a network.

The three no-response cases collapse to `NetworkError`. They are distinct in
`Http.Response` and identical to a user: no answer came back, and the action is to
retry. `BadUrl_` is unreachable anyway, since the URL is built from a closed `Region`
and a closed `Period`.

`DecodeError` therefore means exactly one thing — a **2xx** whose body did not match the
shape — which is what makes it worth telling apart from `UpstreamError` in the UI.

-}
interpretResponse : Decoder a -> Http.Response String -> Result Error a
interpretResponse decoder response =
    case response of
        Http.BadUrl_ _ ->
            Err NetworkError

        Http.Timeout_ ->
            Err NetworkError

        Http.NetworkError_ ->
            Err NetworkError

        Http.BadStatus_ metadata _ ->
            Err (UpstreamError metadata.statusCode)

        Http.GoodStatus_ _ body ->
            Json.Decode.decodeString decoder body
                |> Result.mapError (Json.Decode.errorToString >> DecodeError)
