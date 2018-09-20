module Tests exposing (all)

import Dict
import Expect exposing (Expectation)
import Json.Decode as JD exposing (Decoder)
import Json.Encode as JE exposing (Value)
import List
import Maybe exposing (withDefault)
import PortFunnel exposing (GenericMessage)
import PortFunnel.WebSocket exposing (Message, decode, encode)
import PortFunnel.WebSocket.InternalMessage exposing (InternalMessage(..))
import Test exposing (..)


testMap : (x -> String -> Test) -> List x -> List Test
testMap test data =
    let
        numbers =
            List.map String.fromInt <| List.range 1 (List.length data)
    in
    List.map2 test data numbers


all : Test
all =
    Test.concat <|
        List.concat
            [ testMap encodeDecodeTest messages
            ]


expectResult : Result String a -> Result String a -> Expectation
expectResult sb was =
    case was of
        Err pm ->
            case sb of
                Err _ ->
                    Expect.true "You shouldn't ever see this." True

                Ok _ ->
                    Expect.false pm True

        Ok wasv ->
            case sb of
                Err _ ->
                    Expect.false "Expected an error but didn't get one." True

                Ok sbv ->
                    Expect.equal sbv wasv


encodeDecodeTest : Message -> String -> Test
encodeDecodeTest message name =
    test ("encodeDecode #" ++ name)
        (\_ ->
            expectResult (Ok message) (decode <| encode message)
        )


messages : List Message
messages =
    [ POOpen
        { key = "thekey"
        , url = "theurl"
        }
    , POSend
        { key = "thekey"
        , message = "hello"
        }
    , POClose
        { key = "anotherkey"
        , reason = "because"
        }
    , PLoopOpen
        { key = "thekey"
        , url = "theurl"
        }
    , PLoopSend
        { key = "thekey"
        , message = "hello"
        }
    , PLoopClose
        { key = "anotherkey"
        , reason = "because"
        }
    , POBytesQueued { key = "anotherkey" }
    , PODelay
        { millis = 20
        , id = "1"
        }
    , PIConnected
        { key = "somekey"
        , description = "bloody fine"
        }
    , PIMessageReceived
        { key = "somekey"
        , message = "Earth to Bob. Come in Bob"
        }
    , PIClosed
        { key = "somekey"
        , bytesQueued = 0
        , code = 1000 --normal close
        , reason = "because we like you"
        , wasClean = True
        }
    , PIClosed
        { key = "somekey"
        , bytesQueued = 12
        , code = 1006 --abnormal closure
        , reason = "I had a bad day"
        , wasClean = False
        }
    , PIBytesQueued
        { key = "somekey"
        , bufferedAmount = 12
        }
    , PIDelayed { id = "2" }
    , PIError
        { key = Just "somekey"
        , code = "green"
        , description = "You rock!"
        , name = Just "SecurityError"
        , message = Just "Please close the door."
        }
    , PIError
        { key = Just "somekey"
        , code = "orange"
        , description = "Hit me with your best shot"
        , name = Nothing
        , message = Nothing
        }
    , PIError
        { key = Nothing
        , code = "green"
        , description = "You rock!"
        , name = Nothing
        , message = Nothing
        }
    ]
