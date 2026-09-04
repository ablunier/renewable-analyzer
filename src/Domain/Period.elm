module Domain.Period exposing
    ( Granularity(..)
    , Pair(..)
    , Period(..)
    , YearMonth
    , daysInMonth
    , endDate
    , first
    , granularity
    , granularityOf
    , label
    , monthNumber
    , second
    , startDate
    , timeTrunc
    )

import Time exposing (Month(..))


{-| The two periods being compared, and the API parameters they derive.

Three properties are structural here rather than checked at runtime.

**start ≤ end cannot be violated.** A `Period` is not a date pair; it is a whole year or
a whole month. Its start and end are _computed_ from it, so there is no inverted range
to reject and no smart constructor returning `Result`. The alternative — a start/end
pair with a validating constructor — obtains the same guarantee by check rather than by
construction.

**Only whole years and whole months are representable**, matching the restriction on
the controls. "Is this a whole month?" is not a question anyone can ask, because a
partial month cannot be built.

**Period A and B always share a granularity.** That is what `Pair` is for — see below.

-}
type Period
    = WholeYear Int
    | WholeMonth Int Month


type alias YearMonth =
    { year : Int
    , month : Month
    }


type Granularity
    = Yearly
    | Monthly


{-| A comparison's two periods, where mismatched granularity is **unrepresentable**.

The alternative was to hold two independent `Period` values and reject a mismatch in
`Comparison`'s constructor with a `Result`. This is stronger: there is no error case to
handle, no error message to write, and no code path where a year is compared to a month.

That matters because the comparison is in absolute MWh. "January 2024 vs all of 2023"
would render a -92% delta that means nothing at all — the kind of plausible-looking
wrong answer this project exists to not produce.

-}
type Pair
    = Years Int Int
    | Months YearMonth YearMonth


first : Pair -> Period
first pair =
    case pair of
        Years a _ ->
            WholeYear a

        Months a _ ->
            WholeMonth a.year a.month


second : Pair -> Period
second pair =
    case pair of
        Years _ b ->
            WholeYear b

        Months _ b ->
            WholeMonth b.year b.month


{-| Total, and needs no `Maybe` — which is the payoff of the `Pair` shape. With two
loose `Period`s this would have to return `Maybe Granularity` to cover the mismatch.
-}
granularity : Pair -> Granularity
granularity pair =
    case pair of
        Years _ _ ->
            Yearly

        Months _ _ ->
            Monthly


granularityOf : Period -> Granularity
granularityOf period =
    case period of
        WholeYear _ ->
            Yearly

        WholeMonth _ _ ->
            Monthly


{-| The `time_trunc` request parameter.

Only `year` and `month` exist here because only those are reachable at CCAA level —
`hour` returns 400 and `day` returns a 500 with an HTML body.
Including unreachable `Hourly`/`Daily` variants would put two dead branches in every
`case` in the codebase.

-}
timeTrunc : Granularity -> String
timeTrunc g =
    case g of
        Yearly ->
            "year"

        Monthly ->
            "month"


startDate : Period -> String
startDate period =
    case period of
        WholeYear y ->
            isoDate y 1 1 ++ "T00:00"

        WholeMonth y m ->
            isoDate y (monthNumber m) 1 ++ "T00:00"


{-| Note the `23:59`, matching REE's own documented examples. The API treats the range
as inclusive, so an `end_date` of `T00:00` on the last day would still return the whole
period at these aggregations — but there is no reason to diverge from the documented
form and invite a difference we would then have to explain.
-}
endDate : Period -> String
endDate period =
    case period of
        WholeYear y ->
            isoDate y 12 31 ++ "T23:59"

        WholeMonth y m ->
            isoDate y (monthNumber m) (daysInMonth y m) ++ "T23:59"


isoDate : Int -> Int -> Int -> String
isoDate y m d =
    String.fromInt y
        ++ "-"
        ++ pad (String.fromInt m)
        ++ "-"
        ++ pad (String.fromInt d)


pad : String -> String
pad =
    String.padLeft 2 '0'


{-| Gregorian leap rule, in full. `2100` is not a leap year and February 2100 must not
report 29 days; the naive `modBy 4` version is the classic silent off-by-one.
-}
daysInMonth : Int -> Month -> Int
daysInMonth year month =
    case month of
        Jan ->
            31

        Feb ->
            if isLeapYear year then
                29

            else
                28

        Mar ->
            31

        Apr ->
            30

        May ->
            31

        Jun ->
            30

        Jul ->
            31

        Aug ->
            31

        Sep ->
            30

        Oct ->
            31

        Nov ->
            30

        Dec ->
            31


isLeapYear : Int -> Bool
isLeapYear year =
    (modBy 4 year == 0)
        && (modBy 100 year /= 0 || modBy 400 year == 0)


monthNumber : Month -> Int
monthNumber month =
    case month of
        Jan ->
            1

        Feb ->
            2

        Mar ->
            3

        Apr ->
            4

        May ->
            5

        Jun ->
            6

        Jul ->
            7

        Aug ->
            8

        Sep ->
            9

        Oct ->
            10

        Nov ->
            11

        Dec ->
            12


{-| Human label for a period. English month abbreviations against Spanish region names
is a deliberate mix: region names are quotations from REData (see `Domain.Region`),
whereas month names are ours to choose and the rest of the UI is English.
-}
label : Period -> String
label period =
    case period of
        WholeYear y ->
            String.fromInt y

        WholeMonth y m ->
            monthAbbrev m ++ " " ++ String.fromInt y


monthAbbrev : Month -> String
monthAbbrev month =
    case month of
        Jan ->
            "Jan"

        Feb ->
            "Feb"

        Mar ->
            "Mar"

        Apr ->
            "Apr"

        May ->
            "May"

        Jun ->
            "Jun"

        Jul ->
            "Jul"

        Aug ->
            "Aug"

        Sep ->
            "Sep"

        Oct ->
            "Oct"

        Nov ->
            "Nov"

        Dec ->
            "Dec"
