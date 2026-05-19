module Data.Trip exposing
    ( Trip
    , TripField(..)
    , TripForm
    , decoder
    , encoder
    , validator
    )

import Json.Decode as D
import Json.Decode.Pipeline as Pipeline
import Json.Encode as E
import Validate


type alias Trip =
    { budget        : Float
    , coverPhotoUrl : String
    , description   : String
    , endDate       : String
    , id            : String
    , name          : String
    , startDate     : String
    }


type alias TripForm =
    { budget        : String
    , coverPhotoUrl : String
    , description   : String
    , editing       : Maybe Trip
    , endDate       : String
    , errors        : List String
    , name          : String
    , startDate     : String
    }


type TripField
    = TripBudget
    | TripCoverPhoto
    | TripDescription
    | TripEndDate
    | TripName
    | TripStartDate


validator : Validate.Validator String TripForm
validator =
    Validate.all
        [ Validate.ifBlank .name "Trip name is required."
        , Validate.ifTrue (\f -> f.budget /= "" && String.toFloat f.budget == Nothing) "Budget must be a number."
        , Validate.ifTrue (\f -> f.endDate /= "" && f.endDate < f.startDate) "End date must be after start date."
        ]


encoder : Trip -> E.Value
encoder t =
    E.object
        [ ( "_id",           E.string t.id )
        , ( "budget",        E.float t.budget )
        , ( "coverPhotoUrl", E.string t.coverPhotoUrl )
        , ( "description",   E.string t.description )
        , ( "endDate",       E.string t.endDate )
        , ( "name",          E.string t.name )
        , ( "startDate",     E.string t.startDate )
        , ( "type",          E.string "trip" )
        ]


decoder : D.Decoder Trip
decoder =
    D.succeed Trip
        |> Pipeline.required "budget"        D.float
        |> Pipeline.required "coverPhotoUrl" D.string
        |> Pipeline.required "description"   D.string
        |> Pipeline.required "endDate"       D.string
        |> Pipeline.required "_id"           D.string
        |> Pipeline.required "name"          D.string
        |> Pipeline.required "startDate"     D.string
