module Cluster exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Http
import Json.Decode exposing (Decoder, int, string, list, at, field, map3)
import Json.Decode.Pipeline exposing (decode, required)
import Debug

main : Program Never Model Msg
main =
  Html.program
      { init = init
      , view = view
      , update = update
      , subscriptions = \_ -> Sub.none
      }

-- MODEL

type alias Model =
    { data : String
    }

init : (Model, Cmd Msg)
init =
    ( Model "localhost", Cmd.none)

-- UPDATE

api : String
api =
    "http://localhost:8092/api/v1/"

brokersMetaUrl : String
brokersMetaUrl =
    api ++ "brokers"

-- fetchBrokersMeta : Http.Request String
-- fetchBrokersMeta :
--     Http.getString brokersMetaUrl

-- fetchBrokersMetaCmd : Cmd Msg
-- fetchBrokersMetaCmd =
--     Http.send FetchBrokersMetaCompleted fetchBrokersMeta

-- fetchBrokersMetaCompleted : Model -> Result Http.Error String -> ( Model, Cmd Msg )
-- fetchBrokersMetaCompleted model result =
--     case result of
--         Ok newData ->
--             ( { model | data = newData }, Cmd.none )

--         Err _ ->
--             ( model, Cmd.none )

type Msg
    = FetchBrokersMeta
    | FetchBrokersMetaCompleted (Result Http.Error String)

fetchBrokersMeta : (Cmd Msg)
fetchBrokersMeta =
    let
        request =
            Http.get brokersMetaUrl decodeJson
    in
        Http.send FetchBrokersMetaCompleted request

type alias Broker =
    { id : Int
    , host : String
    }

brokerDecoder : Decoder Broker
brokerDecoder =
    decode Broker
        |> Json.Decode.Pipeline.required "id" int
        |> Json.Decode.Pipeline.required "host" string

decodeJson =
    at ["brokers"] brokerDecoder

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case Debug.log "Message" msg of
        FetchBrokersMeta ->
            (model, fetchBrokersMeta)

        FetchBrokersMetaCompleted (Ok newData) ->
            ( { model | data = newData }, Cmd.none)

        FetchBrokersMetaCompleted (Err _) ->
            (model, Cmd.none)

-- VIEW

view model =
    div [ class "container" ] [
        h2 [ class "text-center" ] [ text "Kafka brokers" ]
        , p [ class "text-center" ] [
            button [ class "btn btn-success", onClick FetchBrokersMeta ] [ text "Brokers meta" ]
        ]
        -- Blockquote with data
        , blockquote [] [
            p [] [text model.data]
        ]
    ]
