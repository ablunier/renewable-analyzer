module ApiTest exposing (suite)

{-| Tests for the decode/request boundary.

The argument for where tests belong applies with full force here: in Elm the bugs can
only live in the pure functions and at the boundary, and this module _is_ the
boundary. Everything above it is compiler-checked; everything below it is REData's.

So the assertions are about the three things the compiler cannot see — that the shape
we believe in is the shape that arrives, that an absent value stays absent instead of
becoming a zero, and that a failure is classified by its status code rather than by
guessing at its body.

-}

import Api.Decode
import Api.Request
import Dict
import Domain.Breakdown as Breakdown exposing (Breakdown)
import Domain.Period exposing (Period(..))
import Domain.Reading exposing (Reading(..))
import Domain.Region as Region exposing (Region(..))
import Domain.RemoteData exposing (Error(..))
import Domain.Technology exposing (Renewability(..), Technology(..))
import Expect
import Fixtures.Captured as Captured
import Fixtures.Synthetic as Synthetic
import Http
import Json.Decode
import Test exposing (Test, describe, test)
import Time exposing (Month(..))


suite : Test
suite =
    describe "Api"
        [ shapeSuite
        , gapSuite
        , classificationSuite
        , urlSuite
        , responseSuite
        ]



-- HELPERS


decode : Region -> Period -> String -> Result String Breakdown
decode region period body =
    Json.Decode.decodeString (Api.Decode.breakdown region period) body
        |> Result.mapError Json.Decode.errorToString


readingOf : Technology -> Result String Breakdown -> Maybe Reading
readingOf technology =
    Result.toMaybe
        >> Maybe.andThen (Breakdown.find technology)
        >> Maybe.map .reading


{-| The 2014–2018 capture is a five-year response, and every test below asks it for a
single year. That is not a mismatch to work around — it is the sharpest available test
of the reconciliation, because a decoder that ignored the requested period would still
pass on a one-bucket response.
-}
castillaYear : Int -> Result String Breakdown
castillaYear year =
    decode CastillaLaMancha (WholeYear year) Captured.ccaaYear2014To2018



-- SHAPE


shapeSuite : Test
shapeSuite =
    describe "response shape"
        [ test "decodes a real capture" <|
            \_ ->
                castillaYear 2018
                    |> Result.map (\b -> List.length b.technologies)
                    |> Expect.equal (Ok 9)

        --  Ten rows arrive in `included`; nine are technologies and one is the total.
        --  If the total row ever leaked into this list, every sum in the application
        --  would double-count — which is exactly the bug in the API's own `percentage`.
        , test "the total row is routed out of the technology list" <|
            \_ ->
                castillaYear 2018
                    |> Result.map Breakdown.technologies
                    |> Result.map (List.map Domain.Technology.toName)
                    |> Result.map (List.member "Generación total")
                    |> Expect.equal (Ok False)
        , test "the total row becomes the total field" <|
            \_ ->
                castillaYear 2018
                    |> Result.map .total
                    |> Expect.equal (Ok (Measured 21635400.025))

        --  The one assertion that pins the two-timestamps decision. Two `last-update`
        --  timestamps exist and differ; this is the document-level one
        --  (2019-06-12), not the per-indicator one (2019-06-20).
        , test "lastUpdate comes from data.attributes, not from an indicator" <|
            \_ ->
                castillaYear 2018
                    |> Result.map .lastUpdate
                    |> Expect.equal (Ok "2019-06-12T17:00:43.000+02:00")

        --  Neither field appears anywhere in the body; both are stamped on from the
        --  request. See `Api.Decode`'s module comment.
        , test "region and period are carried in from the request" <|
            \_ ->
                castillaYear 2016
                    |> Result.map (\b -> ( b.region, b.period ))
                    |> Expect.equal (Ok ( CastillaLaMancha, WholeYear 2016 ))
        , test "decodes a month capture" <|
            \_ ->
                decode CastillaLaMancha
                    (WholeMonth 2024 Jan)
                    Captured.ccaaMonth2024JanFeb
                    |> readingOf Hidraulica
                    |> Expect.equal (Just (Measured 67854.941))

        --  A response with two buckets, asked for the second one. A decoder that took
        --  `List.head` of `values` rather than matching the datetime would return
        --  January's figure here and look perfectly plausible doing it.
        , test "picks the requested bucket, not the first one in the array" <|
            \_ ->
                decode CastillaLaMancha
                    (WholeMonth 2024 Feb)
                    Captured.ccaaMonth2024JanFeb
                    |> readingOf Hidraulica
                    |> Expect.equal (Just (Measured 66264.144))
        ]



-- GAPS


gapSuite : Test
gapSuite =
    describe "missing data"
        [ --  The ragged series. Carbón has three values and no 2017 entry — no null,
          --  no zero, simply absent from the array.
          test "an absent array entry decodes as Missing, not Measured 0" <|
            \_ ->
                castillaYear 2017
                    |> readingOf Carbon
                    |> Expect.equal (Just Missing)

        --  And the gap is specific to the technology that has it: the same response,
        --  the same period, everything else measured.
        , test "a gap in one technology does not affect the others" <|
            \_ ->
                castillaYear 2017
                    |> readingOf Eolica
                    |> Expect.equal (Just (Measured 7507167.263))
        , test "the technology is still listed when its reading is Missing" <|
            \_ ->
                castillaYear 2017
                    |> Result.map (Breakdown.find Carbon >> (/=) Nothing)
                    |> Expect.equal (Ok True)

        --  Dropping the row instead would understate the region's generation while
        --  looking complete, which is the failure `Reading.Aggregate` exists to make
        --  visible one level up.
        , test "renewableTotal reports Partial when a renewable reading is missing" <|
            \_ ->
                decode CastillaLaMancha (WholeYear 2019) Captured.ccaaYear2014To2018
                    |> Result.map Breakdown.renewableTotal
                    |> Expect.equal (Ok Domain.Reading.NoData)

        --  A period the response does not cover at all. Every reading is Missing and
        --  the total is Missing — not a zeroed-out breakdown that would render as a
        --  real region with no generation.
        , test "a period absent from the response yields Missing throughout" <|
            \_ ->
                decode CastillaLaMancha (WholeYear 2019) Captured.ccaaYear2014To2018
                    |> Result.map
                        (\b ->
                            ( b.total
                            , List.all (.reading >> (==) Missing) b.technologies
                            )
                        )
                    |> Expect.equal (Ok ( Missing, True ))

        --  A validating constructor that rejected negative energy would reject the
        --  API's own output.
        , test "a negative value is preserved" <|
            \_ ->
                castillaYear 2016
                    |> readingOf Carbon
                    |> Expect.equal (Just (Measured -2005.081))
        ]



-- CLASSIFICATION


classificationSuite : Test
classificationSuite =
    describe "technology and renewability"
        [ test "technologies are keyed on title, not on the unstable numeric id" <|
            \_ ->
                castillaYear 2018
                    |> Result.map Breakdown.technologies
                    |> Expect.equal
                        (Ok
                            [ Hidraulica
                            , Nuclear
                            , Carbon
                            , CicloCombinado
                            , Eolica
                            , SolarFotovoltaica
                            , SolarTermica
                            , OtrasRenovables
                            , Cogeneracion
                            ]
                        )
        , test "an unknown title becomes Unrecognised rather than being dropped" <|
            \_ ->
                decode Galicia (WholeMonth 2024 Jan) Synthetic.unrecognisedTechnology
                    |> readingOf (Unrecognised "Geotérmica")
                    |> Expect.equal (Just (Measured 50.0))

        --  The only case where the API's `attributes.type` is allowed to decide: we
        --  have no classification of our own for a name we have never seen.
        , test "renewability falls back to the API for an Unrecognised technology" <|
            \_ ->
                decode Galicia (WholeMonth 2024 Jan) Synthetic.unrecognisedTechnology
                    |> Result.toMaybe
                    |> Maybe.andThen (Breakdown.find (Unrecognised "Geotérmica"))
                    |> Maybe.map .renewability
                    |> Expect.equal (Just Renewable)

        --  And the case where it is not: REData calls non-renewable waste `Renovable`
        --  in 15 of 19 regions. Our table wins wherever we have an opinion.
        , test "our classification overrides the API where they disagree" <|
            \_ ->
                decode Galicia (WholeMonth 2024 Jan) Synthetic.unrecognisedTechnology
                    |> Result.toMaybe
                    |> Maybe.andThen (Breakdown.find ResiduosNoRenovables)
                    |> Maybe.map .renewability
                    |> Expect.equal (Just NonRenewable)

        --  Strict on purpose: an unrecognised `attributes.type` could be a new
        --  structural row, and one of those counted as a technology would inflate
        --  every total on the screen.
        , test "an unknown attributes.type fails the whole response" <|
            \_ ->
                decode Galicia (WholeMonth 2024 Jan) Synthetic.unknownIndicatorType
                    |> Result.mapError (String.contains "Subtotal")
                    |> Expect.equal (Err True)
        ]



-- URL


urlSuite : Test
urlSuite =
    describe "request URL"
        [ test "builds the yearly request" <|
            \_ ->
                Api.Request.url Galicia (WholeYear 2018)
                    |> Expect.equal
                        ("/api/es/datos/generacion/estructura-generacion"
                            ++ "?start_date=2018-01-01T00%3A00"
                            ++ "&end_date=2018-12-31T23%3A59"
                            ++ "&time_trunc=year"
                            ++ "&geo_limit=ccaa"
                            ++ "&geo_ids=17"
                        )

        --  February 2024 is a leap February; the end date has to be the 29th.
        , test "builds the monthly request" <|
            \_ ->
                Api.Request.url CastillaLaMancha (WholeMonth 2024 Feb)
                    |> Expect.equal
                        ("/api/es/datos/generacion/estructura-generacion"
                            ++ "?start_date=2024-02-01T00%3A00"
                            ++ "&end_date=2024-02-29T23%3A59"
                            ++ "&time_trunc=month"
                            ++ "&geo_limit=ccaa"
                            ++ "&geo_ids=7"
                        )

        --  REE's own documented example mixes `geo_trunc` with `geo_limit`. We stay on
        --  one geographic axis; this is the test that keeps it that way.
        , test "never sends geo_trunc" <|
            \_ ->
                Region.all
                    |> List.map (\r -> Api.Request.url r (WholeYear 2024))
                    |> List.filter (String.contains "geo_trunc")
                    |> Expect.equal []
        , test "the URL is relative, so dev and production are identical" <|
            \_ ->
                Api.Request.url Galicia (WholeYear 2018)
                    |> String.startsWith "/api/"
                    |> Expect.equal True
        ]



-- RESPONSE CLASSIFICATION


responseSuite : Test
responseSuite =
    describe "interpretResponse"
        [ test "a 200 carrying a real capture decodes" <|
            \_ ->
                interpret (good Captured.ccaaYear2014To2018)
                    |> Result.map .lastUpdate
                    |> Expect.equal (Ok "2019-06-12T17:00:43.000+02:00")
        , test "a 400 with a JSON error envelope is an UpstreamError" <|
            \_ ->
                interpret (bad 400 Captured.error400TimeTruncHour)
                    |> Expect.equal (Err (UpstreamError 400))
        , test "a 502 with a JSON error envelope is an UpstreamError" <|
            \_ ->
                interpret (bad 502 Captured.error502InvalidGeoId)
                    |> Expect.equal (Err (UpstreamError 502))

        --  The one that matters. The body is a Symfony HTML page; a request layer that
        --  tried to parse it would report "the response was not in the expected format"
        --  when the true answer is "REData returned a 500".
        , test "a 500 with an HTML body is an UpstreamError, never a DecodeError" <|
            \_ ->
                interpret (bad 500 Captured.error500TimeTruncDayHtml)
                    |> Expect.equal (Err (UpstreamError 500))

        --  ...and the proof that it is the status code doing the work, not the body:
        --  the same HTML behind a 200 *is* a decode failure.
        , test "the same HTML behind a 200 is a DecodeError" <|
            \_ ->
                interpret (good Captured.error500TimeTruncDayHtml)
                    |> Result.mapError isDecodeError
                    |> Expect.equal (Err True)
        , test "a 200 whose JSON is the wrong shape is a DecodeError" <|
            \_ ->
                interpret (good """{"data":{"attributes":{}},"included":[]}""")
                    |> Result.mapError isDecodeError
                    |> Expect.equal (Err True)
        , test "no response at all is a NetworkError" <|
            \_ ->
                [ Http.NetworkError_, Http.Timeout_, Http.BadUrl_ "nope" ]
                    |> List.map (interpret >> Result.mapError identity)
                    |> Expect.equal
                        (List.repeat 3 (Err NetworkError))
        ]


interpret : Http.Response String -> Result Error Breakdown
interpret =
    Api.Request.interpretResponse
        (Api.Decode.breakdown CastillaLaMancha (WholeYear 2018))


good : String -> Http.Response String
good =
    Http.GoodStatus_ (metadata 200)


bad : Int -> String -> Http.Response String
bad status =
    Http.BadStatus_ (metadata status)


metadata : Int -> Http.Metadata
metadata status =
    { url = Api.Request.url CastillaLaMancha (WholeYear 2018)
    , statusCode = status
    , statusText = ""
    , headers = Dict.empty
    }


isDecodeError : Error -> Bool
isDecodeError error =
    case error of
        DecodeError _ ->
            True

        _ ->
            False
