module Fixtures.Synthetic exposing (unknownIndicatorType, unrecognisedTechnology)

{-| **Hand-constructed responses. Nothing in this module was ever returned by REData.**

Kept in its own module, away from `Fixtures.Captured`, so that no reader has to work out
which fixtures are evidence and which are constructions. The distinction is not
pedantry here: the `Unrecognised` fixture _cannot_ be a real capture, because if the API
returned a technology name `Domain.Technology` did not cover, the type would have been
extended to cover it. Testing that variant requires inventing input, and inventing
input has to be declared.

Both bodies carry a `"_synthetic"` field at the top level saying so, so the label
travels with the data even if it is copied out of this file. The decoder ignores it —
`Json.Decode` reads only the fields it names.

-}


{-| Two things the captures cannot show, in one small but structurally complete
response.

**`Geotérmica`** is not in `Technology.fromTitle`, so it must arrive as
`Unrecognised "Geotérmica"`. Its `attributes.type` is `Renovable`, and because we have
no classification of our own for a name we have never seen, that is the one case where
the API's field is allowed to decide.

**`Residuos no renovables`** reproduces a real contradiction in REData's own output: it
labels non-renewable waste as `Renovable` in 15 of the 19 regions, which is what
overstates País Vasco's renewable total by 46%. Our own table
must win here and classify it `NonRenewable`. The values are invented; the
disagreement is not.

-}
unrecognisedTechnology : String
unrecognisedTechnology =
    """{
  "_synthetic": "HAND-WRITTEN FIXTURE. Not a real REData response. See tests/Fixtures/Synthetic.elm.",
  "data": {
    "type": "Generación por tecnología",
    "id": "gen1",
    "attributes": {
      "title": "Generación por tecnología",
      "last-update": "2026-09-04T12:00:00.000+02:00",
      "description": null
    }
  },
  "included": [
    {
      "type": "Eólica",
      "id": "10333",
      "groupId": "1",
      "attributes": {
        "title": "Eólica",
        "description": null,
        "color": "#74cdb9",
        "type": "Renovable",
        "magnitude": null,
        "composite": false,
        "last-update": "2026-09-04T12:00:00.000+02:00",
        "values": [
          { "value": 1000.0, "percentage": 0.25, "datetime": "2024-01-01T00:00:00.000+01:00" }
        ]
      }
    },
    {
      "type": "Geotérmica",
      "id": "99001",
      "groupId": "1",
      "attributes": {
        "title": "Geotérmica",
        "description": null,
        "color": "#c4986a",
        "type": "Renovable",
        "magnitude": null,
        "composite": false,
        "last-update": "2026-09-04T12:00:00.000+02:00",
        "values": [
          { "value": 50.0, "percentage": 0.0125, "datetime": "2024-01-01T00:00:00.000+01:00" }
        ]
      }
    },
    {
      "type": "Residuos no renovables",
      "id": "10336",
      "groupId": "1",
      "attributes": {
        "title": "Residuos no renovables",
        "description": null,
        "color": "#8bbe1b",
        "type": "Renovable",
        "magnitude": null,
        "composite": false,
        "last-update": "2026-09-04T12:00:00.000+02:00",
        "values": [
          { "value": 25.0, "percentage": 0.00625, "datetime": "2024-01-01T00:00:00.000+01:00" }
        ]
      }
    },
    {
      "type": "Generación total",
      "id": "10338",
      "groupId": "1",
      "attributes": {
        "title": "Generación total",
        "description": null,
        "color": "#f4d44d",
        "type": "total",
        "magnitude": null,
        "composite": false,
        "last-update": "2026-09-04T12:00:00.000+02:00",
        "values": [
          { "value": 2000.0, "percentage": 1.0, "datetime": "2024-01-01T00:00:00.000+01:00" }
        ]
      }
    }
  ]
}"""


{-| An indicator whose `attributes.type` is neither `"total"` nor a renewability.

The decoder rejects the whole response rather than guessing where the row belongs. See
`Api.Decode.role` for why the strict side of that fork was taken: the field's only
unique job is deciding denominator-versus-numerator, and a subtotal row silently
counted as a technology would inflate every figure on the screen.

-}
unknownIndicatorType : String
unknownIndicatorType =
    """{
  "_synthetic": "HAND-WRITTEN FIXTURE. Not a real REData response. See tests/Fixtures/Synthetic.elm.",
  "data": {
    "type": "Generación por tecnología",
    "id": "gen1",
    "attributes": {
      "title": "Generación por tecnología",
      "last-update": "2026-09-04T12:00:00.000+02:00",
      "description": null
    }
  },
  "included": [
    {
      "type": "Subtotal renovable",
      "id": "99002",
      "groupId": "1",
      "attributes": {
        "title": "Subtotal renovable",
        "description": null,
        "color": "#74cdb9",
        "type": "Subtotal",
        "magnitude": null,
        "composite": false,
        "last-update": "2026-09-04T12:00:00.000+02:00",
        "values": [
          { "value": 1050.0, "percentage": 0.5, "datetime": "2024-01-01T00:00:00.000+01:00" }
        ]
      }
    }
  ]
}"""
