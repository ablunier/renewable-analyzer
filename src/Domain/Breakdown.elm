module Domain.Breakdown exposing
    ( Breakdown
    , TechnologyReading
    , find
    , nonRenewableTotal
    , renewableTotal
    , technologies
    )

import Domain.Period exposing (Period)
import Domain.Reading as Reading exposing (Aggregate, Reading)
import Domain.Region exposing (Region)
import Domain.Technology exposing (Renewability(..), Technology)


{-| What one request actually returns: one region, one period, the per-technology
figures, and the total they are a share of.

This is the primary decoded type rather than a `Series`, because for the headline
comparison a whole-year or whole-month request returns **exactly one datapoint per
technology**. A `Series` here would be a length-1 list dressed up as a time series.
Multi-point series only arise for the should-have monthly strip, which gets its own type
if it is built.

`total` is a field, not something computed by summing `technologies`. That is
deliberate and load-bearing: `Generación total` arrives as its own row, and summing the
technologies instead would drift from REE's own figure and would break the moment a
technology is missing. It also means the share denominator is always present in the same
value as its numerators — they cannot be paired wrongly.

A plain record rather than an opaque type: the only invariant worth protecting is "the
total exists", and the field list already guarantees that. An opaque wrapper with
accessors would add ceremony without adding a guarantee. (`Series`, if the strip is
built, is the opposite case — non-empty and ordered are real invariants that need a
smart constructor.)

-}
type alias Breakdown =
    { region : Region
    , period : Period
    , lastUpdate : String
    , total : Reading
    , technologies : List TechnologyReading
    }


{-| `renewability` is resolved at the boundary and stored, not recomputed on demand.

It is stored because it is not a pure function of `technology` alone: for an
`Unrecognised` technology it falls back to the API's `attributes.type`, which is
information that only exists in the response. Storing it keeps that resolution in one
place — the decoder — instead of requiring every call site to have the API's field to
hand.

-}
type alias TechnologyReading =
    { technology : Technology
    , renewability : Renewability
    , reading : Reading
    }


{-| The headline number. Returns an `Aggregate`, so a gap in any renewable technology
surfaces as `Partial` rather than silently shrinking the total.
-}
renewableTotal : Breakdown -> Aggregate
renewableTotal =
    totalOf Renewable


nonRenewableTotal : Breakdown -> Aggregate
nonRenewableTotal =
    totalOf NonRenewable


totalOf : Renewability -> Breakdown -> Aggregate
totalOf wanted breakdown =
    breakdown.technologies
        |> List.filter (\t -> t.renewability == wanted)
        |> List.map .reading
        |> Reading.sum


technologies : Breakdown -> List Technology
technologies breakdown =
    List.map .technology breakdown.technologies


find : Technology -> Breakdown -> Maybe TechnologyReading
find technology breakdown =
    breakdown.technologies
        |> List.filter (\t -> t.technology == technology)
        |> List.head
