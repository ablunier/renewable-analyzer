module Domain.Technology exposing
    ( Renewability(..)
    , Technology(..)
    , fromTitle
    , isRenewable
    , ourClassification
    , resolveRenewability
    , toName
    )

{-| Generation technologies, and the renewable/non-renewable question.

Two decisions are encoded here, both forced by what the API actually returns.

**1. `Unrecognised String` is justified by real data, not prudence.** The indicator set
varies by scope (9 at CCAA level, 16 nationally) and over time (`Carbón` appears
2014–2016 and vanishes from 2017). `Fuel + Gas`, `Turbina de vapor` and `Hidroeólica`
each appear in only 2–3 of the 19 regions. Dropping an unknown technology would
silently understate a region's generation; the type refuses to let us.

**2. We classify renewability ourselves, and do not trust the API's field.** Every
indicator carries `attributes.type` = `Renovable` | `No-Renovable` | `total`. That
field contradicts itself: `Residuos no renovables` — non-renewable waste — is labelled
`Renovable` in 15 of 19 regions. Trusting it overstates País Vasco's renewable total by
**46%**.

-}


{-| Note what is _absent_: there is no `Total` variant.

`Generación total` arrives in the same `included` array as the technologies, but it is
not a technology — it is the denominator. Modelling it as a variant would mean every
sum in the application risks double-counting, and `List.sum` over technologies would
silently return twice the real figure. (That is not hypothetical: it is precisely the
bug in the API's own `percentage` field, which divides by a denominator that includes
the total row and so reports exactly half of every true share.)

So the decoder routes it out structurally on `attributes.type == "total"` — no title
matching — and hands it back separately. See `Domain.Breakdown`.

-}
type Technology
    = Hidraulica
    | Eolica
    | SolarFotovoltaica
    | SolarTermica
    | OtrasRenovables
    | ResiduosRenovables
    | Hidroeolica
    | Nuclear
    | Carbon
    | CicloCombinado
    | Cogeneracion
    | MotoresDiesel
    | TurbinaDeGas
    | TurbinaDeVapor
    | FuelGas
    | ResiduosNoRenovables
    | Unrecognised String


{-| Keyed on `title`, deliberately, despite the indicators carrying a numeric `id` that
looks like the better key.

The id is **not stable**: the same technology has different ids depending on which
id-family serves the region, offset by exactly 42. `Generación total` is `10338` for
the 15 plain CCAA ids and `10296` for the four `874x` regions. An id-keyed decoder
would need both families hardcoded and would fail silently on a family we guessed
wrong. The Spanish display string is the stable identifier.

-}
fromTitle : String -> Technology
fromTitle title =
    case title of
        "Hidráulica" ->
            Hidraulica

        "Eólica" ->
            Eolica

        "Solar fotovoltaica" ->
            SolarFotovoltaica

        "Solar térmica" ->
            SolarTermica

        "Otras renovables" ->
            OtrasRenovables

        "Residuos renovables" ->
            ResiduosRenovables

        "Hidroeólica" ->
            Hidroeolica

        "Nuclear" ->
            Nuclear

        "Carbón" ->
            Carbon

        "Ciclo combinado" ->
            CicloCombinado

        "Cogeneración" ->
            Cogeneracion

        "Motores diésel" ->
            MotoresDiesel

        "Turbina de gas" ->
            TurbinaDeGas

        "Turbina de vapor" ->
            TurbinaDeVapor

        "Fuel + Gas" ->
            FuelGas

        "Residuos no renovables" ->
            ResiduosNoRenovables

        other ->
            Unrecognised other


{-| An unrecognised technology renders under the API's own name rather than as
"Unknown". The user is better served seeing what REData actually called it.
-}
toName : Technology -> String
toName technology =
    case technology of
        Hidraulica ->
            "Hidráulica"

        Eolica ->
            "Eólica"

        SolarFotovoltaica ->
            "Solar fotovoltaica"

        SolarTermica ->
            "Solar térmica"

        OtrasRenovables ->
            "Otras renovables"

        ResiduosRenovables ->
            "Residuos renovables"

        Hidroeolica ->
            "Hidroeólica"

        Nuclear ->
            "Nuclear"

        Carbon ->
            "Carbón"

        CicloCombinado ->
            "Ciclo combinado"

        Cogeneracion ->
            "Cogeneración"

        MotoresDiesel ->
            "Motores diésel"

        TurbinaDeGas ->
            "Turbina de gas"

        TurbinaDeVapor ->
            "Turbina de vapor"

        FuelGas ->
            "Fuel + Gas"

        ResiduosNoRenovables ->
            "Residuos no renovables"

        Unrecognised title ->
            title


type Renewability
    = Renewable
    | NonRenewable


{-| Our classification. `Nothing` **only** for `Unrecognised`, where we genuinely have
no basis to judge — we will not guess a renewability from a string we have never seen.

Exposed separately from `resolveRenewability` so a test can diff it against the API's
field across the captured fixtures. That test is what pins the `Residuos no renovables`
divergence as a known, expected disagreement rather than a surprise.

-}
ourClassification : Technology -> Maybe Renewability
ourClassification technology =
    case technology of
        Hidraulica ->
            Just Renewable

        Eolica ->
            Just Renewable

        SolarFotovoltaica ->
            Just Renewable

        SolarTermica ->
            Just Renewable

        OtrasRenovables ->
            Just Renewable

        ResiduosRenovables ->
            Just Renewable

        Hidroeolica ->
            Just Renewable

        Nuclear ->
            Just NonRenewable

        Carbon ->
            Just NonRenewable

        CicloCombinado ->
            Just NonRenewable

        Cogeneracion ->
            Just NonRenewable

        MotoresDiesel ->
            Just NonRenewable

        TurbinaDeGas ->
            Just NonRenewable

        TurbinaDeVapor ->
            Just NonRenewable

        FuelGas ->
            Just NonRenewable

        ResiduosNoRenovables ->
            Just NonRenewable

        Unrecognised _ ->
            Nothing


{-| The boundary function. Ours wins where we have an opinion; the API's field is the
fallback for a technology we have never seen.

The `Maybe` above never escapes the decoder — this returns a total `Renewability`, so
no downstream code carries an "unclassified" branch. That is the whole point of
resolving it at the boundary: parse, don't validate.

-}
resolveRenewability : Technology -> Renewability -> Renewability
resolveRenewability technology apiSays =
    ourClassification technology
        |> Maybe.withDefault apiSays


isRenewable : Renewability -> Bool
isRenewable renewability =
    case renewability of
        Renewable ->
            True

        NonRenewable ->
            False
