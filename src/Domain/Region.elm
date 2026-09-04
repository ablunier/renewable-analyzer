module Domain.Region exposing
    ( GeoId
    , Region(..)
    , all
    , default
    , geoIdToString
    , geoLimit
    , toGeoId
    , toName
    )

{-| The 19 Spanish autonomous communities and cities, as REData scopes them.

Every id here is confirmed against REE's own published table. That matters
for the shape of this module: because all 19 are confirmed, `Region` is a
genuinely closed set with no `Unrecognised` variant and `toGeoId` is total.
There is no `Maybe` anywhere near it.

Contrast with `Domain.Technology`, which _does_ carry an `Unrecognised` variant. The
difference is not stylistic. Spanish administrative geography is fixed and we hold
the complete list; the API's technology vocabulary is open and varies by scope and by
year. The type system should say which is which.

-}


{-| Note on naming: variants are ASCII so the source stays keyboard-typeable, while
`toName` returns REE's own accented wording. The two are deliberately allowed to
differ — the variant is our identifier, `toName` is a quotation.
-}
type Region
    = Andalucia
    | Aragon
    | Cantabria
    | CastillaLaMancha
    | CastillaYLeon
    | Cataluna
    | Ceuta
    | Madrid
    | Melilla
    | Navarra
    | ComunidadValenciana
    | Extremadura
    | Galicia
    | IslasBaleares
    | IslasCanarias
    | LaRioja
    | PaisVasco
    | Asturias
    | Murcia


{-| Drives the selector. Because this is a hand-written list over a closed type,
adding a variant does not automatically add it here — so the module is covered by a
test asserting `List.length all == 19` and that every variant round-trips. That test
is the thing standing in for exhaustiveness; Elm cannot enumerate a custom type.

Ordered alphabetically by display name, which is what a user scanning a dropdown
expects. REE's own selector is ordered by geo id, which is meaningless to a reader.

-}
all : List Region
all =
    [ Andalucia
    , Aragon
    , Cantabria
    , CastillaLaMancha
    , CastillaYLeon
    , Cataluna
    , Ceuta
    , Madrid
    , Melilla
    , Navarra
    , ComunidadValenciana
    , Extremadura
    , Galicia
    , IslasBaleares
    , IslasCanarias
    , LaRioja
    , PaisVasco
    , Asturias
    , Murcia
    ]


{-| default to Galicia.
-}
default : Region
default =
    Galicia


{-| REE's own wording, so a user cross-checking against ree.es sees the same label.

The one place this is contestable is Navarra: REE writes "Comunidad de Navarra", while
the Spanish constitution says "Comunidad Foral de Navarra".
Quoting the data source wins here for consistency with the cited table, but it is a
one-line change if you would rather show the formal name.

-}
toName : Region -> String
toName region =
    case region of
        Andalucia ->
            "Andalucía"

        Aragon ->
            "Aragón"

        Cantabria ->
            "Cantabria"

        CastillaLaMancha ->
            "Castilla la Mancha"

        CastillaYLeon ->
            "Castilla y León"

        Cataluna ->
            "Cataluña"

        Ceuta ->
            "Comunidad de Ceuta"

        Madrid ->
            "Comunidad de Madrid"

        Melilla ->
            "Comunidad de Melilla"

        Navarra ->
            "Comunidad de Navarra"

        ComunidadValenciana ->
            "Comunidad Valenciana"

        Extremadura ->
            "Extremadura"

        Galicia ->
            "Galicia"

        IslasBaleares ->
            "Islas Baleares"

        IslasCanarias ->
            "Islas Canarias"

        LaRioja ->
            "La Rioja"

        PaisVasco ->
            "País Vasco"

        Asturias ->
            "Principado de Asturias"

        Murcia ->
            "Región de Murcia"


{-| Opaque on purpose. The constructor is not exposed, so the only way to obtain a
`GeoId` is `toGeoId`, and therefore the only ids that can reach a request are ones
that came from a confirmed `Region`. A bare `Int` would let any caller invent `9999`
and get a cached 502 back.
-}
type GeoId
    = GeoId Int


geoIdToString : GeoId -> String
geoIdToString (GeoId id) =
    String.fromInt id


{-| The confirmed id table.

Four of these look wrong and are not: Islas Canarias, Islas Baleares, Ceuta and
Melilla are served by the _electric-system_ ids 8742–8745. That is REE's own mapping,
not a mix-up on our side — REE prescribes `geo_limit=ccaa` for them all the same.
It is the reason `geoLimit` below is a module-level constant rather than something a
caller chooses.

-}
toGeoId : Region -> GeoId
toGeoId region =
    GeoId <|
        case region of
            Andalucia ->
                4

            Aragon ->
                5

            Cantabria ->
                6

            CastillaLaMancha ->
                7

            CastillaYLeon ->
                8

            Cataluna ->
                9

            PaisVasco ->
                10

            Asturias ->
                11

            Madrid ->
                13

            Navarra ->
                14

            ComunidadValenciana ->
                15

            Extremadura ->
                16

            Galicia ->
                17

            LaRioja ->
                20

            Murcia ->
                21

            IslasCanarias ->
                8742

            IslasBaleares ->
                8743

            Ceuta ->
                8744

            Melilla ->
                8745


{-| Constant, not a function of `Region`, and not a label.

Two findings force this shape. First, all 19 confirmed regions take `geo_limit=ccaa`,
so there is nothing to vary. Second — and this is the important one — `geo_limit` does
**not** select the geography: `geo_ids=8742` returns identical data under
`geo_limit=ccaa` and `geo_limit=canarias`. It only gates which ids are legal. Exposing
it as a per-region value would invite reading it back as a region name, which is
exactly the silent mislabelling this module exists to prevent.

-}
geoLimit : String
geoLimit =
    "ccaa"
