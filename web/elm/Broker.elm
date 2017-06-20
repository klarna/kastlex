module Broker exposing (..)

type alias Broker =
    { id : Int
    , host : String
    , endpoints : List String
    }
