module View.Value exposing
    ( columnHeading
    , decimalsFor
    , fixed
    , formatQuantity
    , formatSignedQuantity
    , gap
    , groupThousands
    , numericColumnHeading
    , renewabilityLabel
    , roundTo
    , rowHeading
    , signed
    , viewDisplayable
    , viewSignedQuantity
    )

{-| Every figure on screen, and the words that stand in for one that is absent.

Nothing here returns `Html Msg`, and that is the module's whole claim. These are
projections of domain values, not controls: `Html msg` is the compiler certifying that no
cell in a table can originate an event, which is why this module needs neither `Main`'s
`Model` nor its `Msg` and can sit below both. A function that acquires a handler has
stopped belonging here, and the type says so before the reviewer has to.

Rendering and table furniture share one module because they share one rule: **an absent
figure is never a dash and never a zero.** A dash in a numeric column is read as a zero by
anyone scanning it, so absence is always words — "not measured", "share undefined" — set
in a style no one can mistake for a number. `Domain.Reading` keeps absence out of the
arithmetic; this module keeps it out of the digits.

-}

import Domain.Comparison as Comparison exposing (Direction(..))
import Domain.Measure as Measure exposing (Displayable(..), Quantity)
import Domain.Technology as Technology exposing (Renewability)
import Html exposing (Html, span, text, th)
import Html.Attributes exposing (class, scope)



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
