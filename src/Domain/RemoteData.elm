module Domain.RemoteData exposing
    ( Error(..)
    , RemoteData(..)
    , errorMessage
    , isLoading
    , map
    , toMaybe
    )

{-| Loading state as one type, rather than a record of three `Maybe`s and a `Bool`.

Written by hand rather than pulled from `krisajenkins/remotedata`. The value is that the
four states are mutually exclusive _by construction_: there is no way to represent
"loading and also failed", which a `{ data : Maybe a, error : Maybe e, loading : Bool }`
happily allows and which every such record eventually contains.

-}


type RemoteData a
    = NotAsked
    | Loading
    | Failure Error
    | Success a


{-| `UpstreamError` carries the status because the codes are meaningful here: **502** is an
unknown `geo_ids`, **400** is an unsupported `time_trunc` _or_ an over-long date range,
and **500** arrives with an HTML body. None of them should be surfaced with the API's
own `detail` text, which says "try again later" even for the permanently-cached 502.
-}
type Error
    = NetworkError
    | UpstreamError Int
    | DecodeError String


map : (a -> b) -> RemoteData a -> RemoteData b
map f data =
    case data of
        NotAsked ->
            NotAsked

        Loading ->
            Loading

        Failure error ->
            Failure error

        Success value ->
            Success (f value)


toMaybe : RemoteData a -> Maybe a
toMaybe data =
    case data of
        Success value ->
            Just value

        _ ->
            Nothing


isLoading : RemoteData a -> Bool
isLoading data =
    case data of
        Loading ->
            True

        _ ->
            False


{-| Deliberately never passes the upstream `detail` string through. REData returns
"Inténtelo de nuevo más tarde" ("try again later") for a 502 caused by an id that will
never be valid — advice that is simply false, and telling a user to retry forever is
worse than saying nothing.
-}
errorMessage : Error -> String
errorMessage error =
    case error of
        NetworkError ->
            "Could not reach the server. Check your connection and retry."

        UpstreamError 400 ->
            "REData rejected this request. The date range may be too long — yearly data is capped at 5 years, monthly at 24 months."

        UpstreamError 502 ->
            "REData has no data for this region and period."

        UpstreamError status ->
            "REData returned an error (HTTP " ++ String.fromInt status ++ ")."

        DecodeError details ->
            "The response was not in the expected format: " ++ details
