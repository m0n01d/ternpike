module Data.Void exposing (Void, decoder)

import Json.Decode as D
import Json.Decode.Pipeline as Pipeline


type alias Void =
    { createdAt : String
    , id        : String
    , targetId  : String
    }


decoder : D.Decoder Void
decoder =
    D.succeed Void
        |> Pipeline.required "createdAt" D.string
        |> Pipeline.required "_id"       D.string
        |> Pipeline.required "targetId"  D.string
