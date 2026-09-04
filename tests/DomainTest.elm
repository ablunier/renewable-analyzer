module DomainTest exposing (suite)

{-| Tests for the domain model.

Aimed where the risk actually is. Most of the guarantees need no test at all — that a
year cannot be compared to a month, or that a `GeoId` cannot be invented, are enforced
by the compiler and a test asserting them would not compile. What is left is the part
the compiler cannot check: hand-written lists, arithmetic, and ordering.

-}

import Domain.Breakdown exposing (Breakdown, TechnologyReading)
import Domain.Comparison as Comparison
import Domain.Measure as Measure exposing (Displayable(..), Measure(..), Quantity(..))
import Domain.Period as Period exposing (Period(..))
import Domain.Reading as Reading exposing (Aggregate(..), Reading(..))
import Domain.Region as Region
import Domain.Technology as Technology exposing (Renewability(..), Technology(..))
import Expect
import Test exposing (Test, describe, test)
import Time exposing (Month(..))


suite : Test
suite =
    describe "Domain"
        [ regionSuite
        , technologySuite
        , periodSuite
        , readingSuite
        , measureSuite
        , comparisonSuite
        ]



-- REGION


regionSuite : Test
regionSuite =
    describe "Region"
        [ test "all lists exactly the 19 confirmed communities and cities" <|
            \_ ->
                List.length Region.all |> Expect.equal 19

        --  `all` is hand-written over a closed type; Elm cannot enumerate custom type
        --  variants, so this is what stands in for exhaustiveness. Without it, adding a
        --  variant compiles fine and the region is silently missing from the dropdown —
        --  precisely the drift a TypeScript hand-maintained array suffers from.
        , test "no duplicate regions in all" <|
            \_ ->
                List.length (unique (List.map Region.toName Region.all))
                    |> Expect.equal (List.length Region.all)
        , test "every region maps to a distinct name" <|
            \_ ->
                List.length (unique (List.map Region.toName Region.all))
                    |> Expect.equal 19

        --  Ids are NOT distinct across all 19 and must not be asserted to be: REE serves
        --  Islas Canarias/Baleares/Ceuta/Melilla from the electric-system ids. This test
        --  pins that surprise so nobody "fixes" it later.
        , test "the four island and city communities reuse electric-system ids" <|
            \_ ->
                List.map (Region.toGeoId >> Region.geoIdToString)
                    [ Region.IslasCanarias, Region.IslasBaleares, Region.Ceuta, Region.Melilla ]
                    |> Expect.equal [ "8742", "8743", "8744", "8745" ]
        , test "the other fifteen have distinct ids" <|
            \_ ->
                let
                    ids =
                        Region.all
                            |> List.filter
                                (\r ->
                                    not (List.member r [ Region.IslasCanarias, Region.IslasBaleares, Region.Ceuta, Region.Melilla ])
                                )
                            |> List.map (Region.toGeoId >> Region.geoIdToString)
                in
                List.length (unique ids) |> Expect.equal 15
        , test "default region is Galicia" <|
            \_ ->
                Region.toName Region.default |> Expect.equal "Galicia"
        ]



-- TECHNOLOGY


technologySuite : Test
technologySuite =
    describe "Technology"
        [ test "every title seen in the 19-region capture round-trips" <|
            \_ ->
                let
                    captured =
                        [ "Hidráulica"
                        , "Eólica"
                        , "Solar fotovoltaica"
                        , "Solar térmica"
                        , "Otras renovables"
                        , "Residuos renovables"
                        , "Hidroeólica"
                        , "Nuclear"
                        , "Carbón"
                        , "Ciclo combinado"
                        , "Cogeneración"
                        , "Motores diésel"
                        , "Turbina de gas"
                        , "Turbina de vapor"
                        , "Fuel + Gas"
                        , "Residuos no renovables"
                        ]
                in
                captured
                    |> List.map (Technology.fromTitle >> Technology.toName)
                    |> Expect.equal captured
        , test "an unseen title becomes Unrecognised, not a silent drop" <|
            \_ ->
                Technology.fromTitle "Fusión"
                    |> Expect.equal (Unrecognised "Fusión")
        , test "an unrecognised technology still renders under REData's own name" <|
            \_ ->
                Technology.fromTitle "Fusión"
                    |> Technology.toName
                    |> Expect.equal "Fusión"

        --  Our classification must contradict the API here: REData calls non-renewable
        --  waste `Renovable` in 15 of 19 regions, which overstates País Vasco's renewable
        --  total by 46%.
        , test "we classify Residuos no renovables as non-renewable, against the API" <|
            \_ ->
                Technology.resolveRenewability ResiduosNoRenovables Renewable
                    |> Expect.equal NonRenewable
        , test "our classification wins over the API's for every recognised technology" <|
            \_ ->
                [ Eolica, Nuclear, Carbon, ResiduosNoRenovables, Hidroeolica ]
                    |> List.map (\t -> Technology.resolveRenewability t Renewable)
                    |> Expect.equal [ Renewable, NonRenewable, NonRenewable, NonRenewable, Renewable ]
        , test "the API's field is the fallback only for Unrecognised" <|
            \_ ->
                Expect.all
                    [ \_ ->
                        Technology.resolveRenewability (Unrecognised "Fusión") Renewable
                            |> Expect.equal Renewable
                    , \_ ->
                        Technology.resolveRenewability (Unrecognised "Fusión") NonRenewable
                            |> Expect.equal NonRenewable
                    ]
                    ()
        ]



-- PERIOD


periodSuite : Test
periodSuite =
    describe "Period"
        [ test "a whole year derives an inclusive full-year range" <|
            \_ ->
                Expect.all
                    [ \p -> Period.startDate p |> Expect.equal "2023-01-01T00:00"
                    , \p -> Period.endDate p |> Expect.equal "2023-12-31T23:59"
                    ]
                    (WholeYear 2023)
        , test "a whole month derives that month's real last day" <|
            \_ ->
                Period.endDate (WholeMonth 2023 Apr) |> Expect.equal "2023-04-30T23:59"
        , test "February in a leap year has 29 days" <|
            \_ ->
                Period.endDate (WholeMonth 2024 Feb) |> Expect.equal "2024-02-29T23:59"
        , test "February in a common year has 28" <|
            \_ ->
                Period.endDate (WholeMonth 2023 Feb) |> Expect.equal "2023-02-28T23:59"

        --  The century rule. 2100 is divisible by 4 but is not a leap year; the naive
        --  `modBy 4` version returns 29 here and would silently request a date that
        --  does not exist.
        , test "1900 and 2100 are not leap years; 2000 is" <|
            \_ ->
                List.map (\y -> Period.daysInMonth y Feb) [ 1900, 2000, 2100 ]
                    |> Expect.equal [ 28, 29, 28 ]
        , test "months pad to two digits" <|
            \_ ->
                Period.startDate (WholeMonth 2024 Jan) |> Expect.equal "2024-01-01T00:00"
        , test "a Pair always reports one granularity for both periods" <|
            \_ ->
                Expect.all
                    [ \_ -> Period.granularity (Period.Years 2022 2023) |> Expect.equal Period.Yearly
                    , \_ ->
                        Period.granularity
                            (Period.Months { year = 2024, month = Jan } { year = 2024, month = Jun })
                            |> Expect.equal Period.Monthly
                    ]
                    ()
        , test "first and second preserve order" <|
            \_ ->
                Expect.all
                    [ \p -> Period.first p |> Expect.equal (WholeYear 2022)
                    , \p -> Period.second p |> Expect.equal (WholeYear 2023)
                    ]
                    (Period.Years 2022 2023)
        , test "time_trunc matches what the API accepts at CCAA level" <|
            \_ ->
                List.map Period.timeTrunc [ Period.Yearly, Period.Monthly ]
                    |> Expect.equal [ "year", "month" ]
        ]



-- READING


readingSuite : Test
readingSuite =
    describe "Reading"
        [ test "summing complete readings reports Complete" <|
            \_ ->
                Reading.sum [ Measured 10, Measured 5 ]
                    |> Expect.equal (Complete 15)

        --  The important one. A gap must not vanish into the total: summing only the
        --  present values and returning a plain number is the "collapse a gap to zero"
        --  mistake committed one level up, where it is invisible.
        , test "a gap makes the total Partial, not a smaller Complete" <|
            \_ ->
                Reading.sum [ Measured 10, Missing, Measured 5 ]
                    |> Expect.equal (Partial { known = 15, missing = 1 })
        , test "all-missing is NoData, not zero" <|
            \_ ->
                Reading.sum [ Missing, Missing ] |> Expect.equal NoData
        , test "an empty list is NoData, not zero" <|
            \_ ->
                Reading.sum [] |> Expect.equal NoData

        --  Real data: Carbón, Castilla-La Mancha, 2016 = -2005.081. A smart constructor
        --  rejecting negatives would reject the API's own output.
        , test "negative generation is a legitimate measurement" <|
            \_ ->
                -- Compared within a tolerance, not by equality: -2005.081 + 3000 is
                -- 994.9190000000001 in IEEE 754. Any test that asserts exact equality on
                -- summed Floats is testing the float representation, not the domain.
                Reading.sum [ Measured -2005.081, Measured 3000 ]
                    |> Reading.aggregateToMaybe
                    |> Maybe.withDefault 0
                    |> Expect.within (Expect.Absolute 1.0e-9) 994.919
        , test "a negative sum stays Complete, not treated as absent" <|
            \_ ->
                Reading.sum [ Measured -2005.081 ]
                    |> Reading.aggregateToMaybe
                    |> Maybe.withDefault 0
                    |> Expect.within (Expect.Absolute 1.0e-9) -2005.081
        ]



-- MEASURE


measureSuite : Test
measureSuite =
    describe "Measure"
        [ test "energy renders as MWh" <|
            \_ ->
                Measure.display Energy (Measured 1000) (Measured 250)
                    |> Expect.equal (Shown (Megawatthours 250))
        , test "share is computed against total generation, not the API's percentage" <|
            \_ ->
                Measure.display Share (Measured 1000) (Measured 250)
                    |> Expect.equal (Shown (Percentage 25))

        --  The API's own `percentage` field would report 12.5 here, because its
        --  denominator includes the `Generación total` row and is therefore double.
        , test "a missing reading is never rendered as a value" <|
            \_ ->
                Expect.all
                    [ \_ -> Measure.display Energy (Measured 1000) Missing |> Expect.equal NoMeasurement
                    , \_ -> Measure.display Share (Measured 1000) Missing |> Expect.equal NoMeasurement
                    ]
                    ()
        , test "share of a zero total is undefined, not Infinity or 0%" <|
            \_ ->
                Measure.display Share (Measured 0) (Measured 5)
                    |> Expect.equal ShareUndefined
        , test "share is undefined when the total itself was not measured" <|
            \_ ->
                Measure.display Share Missing (Measured 5)
                    |> Expect.equal ShareUndefined
        , test "a quantity carries its own unit" <|
            \_ ->
                List.map Measure.unitLabel [ Megawatthours 1, Percentage 1 ]
                    |> Expect.equal [ "MWh", "%" ]
        , test "negative values still render, with sign preserved" <|
            \_ ->
                Measure.display Energy (Measured 1000) (Measured -2005.081)
                    |> Expect.equal (Shown (Megawatthours -2005.081))
        ]



-- COMPARISON


comparisonSuite : Test
comparisonSuite =
    describe "Comparison"
        [ test "renewableTotal sums only renewable technologies" <|
            \_ ->
                Domain.Breakdown.renewableTotal sampleA
                    |> Expect.equal (Complete 130)
        , test "renewableTotal excludes the Generación total row by construction" <|
            \_ ->
                -- `total` is a separate field, not a technology, so it cannot be summed
                -- in by accident. If it were a Technology variant this would be 1130.
                Domain.Breakdown.renewableTotal sampleA
                    |> Expect.notEqual (Complete 1130)
        , test "a gap in a renewable technology makes the headline Partial" <|
            \_ ->
                Domain.Breakdown.renewableTotal sampleB
                    |> Expect.equal (Partial { known = 155, missing = 1 })
        , test "absolute change is B minus A" <|
            \_ ->
                Comparison.absoluteChange (Measured 100) (Measured 130)
                    |> Expect.equal (Just 30)
        , test "change against a missing reading is unknowable, not zero" <|
            \_ ->
                Expect.all
                    [ \_ -> Comparison.absoluteChange Missing (Measured 130) |> Expect.equal Nothing
                    , \_ -> Comparison.absoluteChange (Measured 100) Missing |> Expect.equal Nothing
                    ]
                    ()
        , test "percent change against a zero baseline is undefined, not Infinity" <|
            \_ ->
                Comparison.percentChange (Measured 0) (Measured 130)
                    |> Expect.equal Nothing
        , test "percent change is signed correctly from a negative baseline" <|
            \_ ->
                -- abs() on the denominator: going from -100 to -50 is an increase.
                Comparison.percentChange (Measured -100) (Measured -50)
                    |> Expect.equal (Just 50)

        --  The workflow decision under test: the technology explaining the change is
        --  first, regardless of its absolute size.
        , test "breakdown is ordered by magnitude of change, not by size or name" <|
            \_ ->
                Comparison.byDifference sampleA sampleB
                    |> List.map (.technology >> Technology.toName)
                    |> Expect.equal [ "Eólica", "Nuclear", "Hidráulica", "Solar fotovoltaica" ]
        , test "technologies with an unknown change sort last, not first" <|
            \_ ->
                Comparison.byDifference sampleA sampleB
                    |> List.reverse
                    |> List.head
                    |> Maybe.andThen .change
                    |> Expect.equal Nothing
        , test "the technology set is the union of both periods" <|
            \_ ->
                -- Solar fotovoltaica exists only in B. Intersecting would hide it, and
                -- hiding an appearing or vanishing technology is hiding the finding.
                Comparison.byDifference sampleA sampleB
                    |> List.map (.technology >> Technology.toName)
                    |> List.member "Solar fotovoltaica"
                    |> Expect.equal True
        , test "direction reads the sign of the change" <|
            \_ ->
                List.map Comparison.direction [ Just 5, Just -5, Just 0, Nothing ]
                    |> Expect.equal [ Comparison.Up, Comparison.Down, Comparison.Flat, Comparison.Flat ]
        ]



-- FIXTURES


{-| Deliberately hand-built, not captured. These exercise arithmetic and ordering, not
decoding — decoder tests belong against real captured responses.
-}
sampleA : Breakdown
sampleA =
    { region = Region.Galicia
    , period = WholeYear 2022
    , lastUpdate = "2024-01-01T00:00:00.000+01:00"
    , total = Measured 1000
    , technologies =
        [ reading Eolica Renewable (Measured 100)
        , reading Hidraulica Renewable (Measured 30)
        , reading Nuclear NonRenewable (Measured 500)
        ]
    }


sampleB : Breakdown
sampleB =
    { region = Region.Galicia
    , period = WholeYear 2023
    , lastUpdate = "2024-01-01T00:00:00.000+01:00"
    , total = Measured 1000
    , technologies =
        [ reading Eolica Renewable (Measured 140)
        , reading Hidraulica Renewable (Measured 15)
        , reading Nuclear NonRenewable (Measured 480)
        , reading SolarFotovoltaica Renewable Missing
        ]
    }


reading : Technology -> Renewability -> Reading -> TechnologyReading
reading technology renewability value =
    { technology = technology
    , renewability = renewability
    , reading = value
    }


unique : List comparable -> List comparable
unique =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                x :: acc
        )
        []
