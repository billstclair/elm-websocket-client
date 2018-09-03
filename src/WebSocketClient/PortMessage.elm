----------------------------------------------------------------------
--
-- PortMessage.elm
-- Communication through the ports to example/site/js/WebSocketClient.js
-- Copyright (c) 2018 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE
--
----------------------------------------------------------------------


module WebSocketClient.PortMessage exposing
    ( Continuation(..)
    , PIClosedRecord
    , PortMessage(..)
    , RawPortMessage
    , decodePortMessage
    , decodeRawPortMessage
    , encodePortMessage
    , encodeRawPortMessage
    , fromRawPortMessage
    , portMessageDecoder
    , rawPortMessageDecoder
    , toRawPortMessage
    )

import Dict exposing (Dict)
import Json.Decode as JD exposing (Decoder)
import Json.Encode as JE exposing (Value)


type alias RawPortMessage =
    { tag : String
    , args : Dict String String
    }


encodeRawPortMessage : RawPortMessage -> Value
encodeRawPortMessage message =
    let
        args =
            Dict.toList message.args
                |> List.map
                    (\( name, value ) ->
                        ( name, JE.string value )
                    )
    in
    JE.object
        [ ( "tag", JE.string message.tag )
        , ( "args", JE.object args )
        ]


rawPortMessageDecoder : Decoder RawPortMessage
rawPortMessageDecoder =
    JD.map2 RawPortMessage
        (JD.field "tag" JD.string)
        (JD.field "args" (JD.dict JD.string))


decodeValue : Decoder a -> Value -> Result String a
decodeValue decoder value =
    case JD.decodeValue decoder value of
        Ok a ->
            Ok a

        Err err ->
            Err <| JD.errorToString err


decodeString : Decoder a -> String -> Result String a
decodeString decoder string =
    case JD.decodeString decoder string of
        Ok a ->
            Ok a

        Err err ->
            Err <| JD.errorToString err


decodeRawPortMessage : Value -> Result String RawPortMessage
decodeRawPortMessage value =
    decodeValue rawPortMessageDecoder value


type alias PIClosedRecord =
    { key : String, code : Int, reason : String, wasClean : Bool }


type Continuation
    = RetryConnection String
    | DrainOutputQueue String


encodeContinuation : Continuation -> String
encodeContinuation continuation =
    JE.encode 0 <|
        case continuation of
            RetryConnection key ->
                JE.object
                    [ ( "tag", JE.string "RetryConnection" )
                    , ( "key", JE.string key )
                    ]

            DrainOutputQueue key ->
                JE.object
                    [ ( "tag", JE.string "DrainOutputQueue" )
                    , ( "key", JE.string key )
                    ]


decodeContinuation : String -> Result String Continuation
decodeContinuation json =
    decodeString continuationDecoder json


continuationDecoder : Decoder Continuation
continuationDecoder =
    JD.field "tag" JD.string
        |> JD.andThen
            (\tag ->
                case tag of
                    "RetryConnection" ->
                        JD.map RetryConnection
                            (JD.field "key" JD.string)

                    "DrainOutputQueue" ->
                        JD.map DrainOutputQueue
                            (JD.field "key" JD.string)

                    _ ->
                        JD.fail "Unknown Continuation tag"
            )


type PortMessage
    = InvalidMessage
      -- output
    | POOpen { key : String, url : String }
    | POSend { key : String, message : String }
    | POClose { key : String, reason : String }
    | POBytesQueued { key : String }
    | PODelay { millis : Int, continuation : Continuation }
      -- input
    | PIConnected { key : String, description : String }
    | PIMessageReceived { key : String, message : String }
    | PIClosed PIClosedRecord
    | PIBytesQueued { key : String, bufferedAmount : Int }
    | PIDelayed { continuation : Continuation }
    | PIError
        { key : Maybe String
        , code : String
        , description : String
        , name : Maybe String
        }


toRawPortMessage : PortMessage -> RawPortMessage
toRawPortMessage portMessage =
    case portMessage of
        POOpen { key, url } ->
            RawPortMessage "open" <|
                Dict.fromList [ ( "key", key ), ( "url", url ) ]

        POSend { key, message } ->
            RawPortMessage "send" <|
                Dict.fromList [ ( "key", key ), ( "message", message ) ]

        POClose { key, reason } ->
            RawPortMessage "close" <|
                Dict.fromList [ ( "key", key ), ( "reason", reason ) ]

        POBytesQueued { key } ->
            RawPortMessage "bytesQueued" <|
                Dict.fromList [ ( "key", key ) ]

        PODelay { millis, continuation } ->
            RawPortMessage "delay" <|
                Dict.fromList
                    [ ( "millis", String.fromInt millis )
                    , ( "continuation", encodeContinuation continuation )
                    ]

        _ ->
            RawPortMessage "invalid" Dict.empty


getDictElements : List comparable -> Dict comparable a -> Maybe (List a)
getDictElements keys dict =
    let
        loop tail res =
            case tail of
                [] ->
                    Just <| List.reverse res

                key :: rest ->
                    case Dict.get key dict of
                        Nothing ->
                            Nothing

                        Just a ->
                            loop rest (a :: res)
    in
    loop keys []


fromRawPortMessage : RawPortMessage -> PortMessage
fromRawPortMessage { tag, args } =
    case tag of
        "connected" ->
            case getDictElements [ "key", "description" ] args of
                Just [ key, description ] ->
                    PIConnected { key = key, description = description }

                _ ->
                    InvalidMessage

        "messageReceived" ->
            case getDictElements [ "key", "message" ] args of
                Just [ key, message ] ->
                    PIMessageReceived { key = key, message = message }

                _ ->
                    InvalidMessage

        "closed" ->
            case getDictElements [ "key", "code", "reason", "wasClean" ] args of
                Just [ key, code, reason, wasClean ] ->
                    PIClosed
                        { key = key
                        , code = Maybe.withDefault -1 <| String.toInt code
                        , reason = reason
                        , wasClean = wasClean == "true"
                        }

                _ ->
                    InvalidMessage

        "bytesQueued" ->
            case getDictElements [ "key", "bufferedAmount" ] args of
                Just [ key, bufferedAmountString ] ->
                    case String.toInt bufferedAmountString of
                        Nothing ->
                            InvalidMessage

                        Just bufferedAmount ->
                            PIBytesQueued
                                { key = key
                                , bufferedAmount = bufferedAmount
                                }

                _ ->
                    InvalidMessage

        "delayed" ->
            case getDictElements [ "continuation" ] args of
                Just [ json ] ->
                    case decodeContinuation json of
                        Err _ ->
                            InvalidMessage

                        Ok continuation ->
                            PIDelayed
                                { continuation = continuation }

                _ ->
                    InvalidMessage

        "error" ->
            case getDictElements [ "code", "description" ] args of
                Just [ code, description ] ->
                    PIError
                        { key = Dict.get "key" args
                        , code = code
                        , description = description
                        , name = Dict.get "name" args
                        }

                _ ->
                    InvalidMessage

        _ ->
            InvalidMessage


encodePortMessage : PortMessage -> Value
encodePortMessage =
    toRawPortMessage >> encodeRawPortMessage


portMessageDecoder : Decoder PortMessage
portMessageDecoder =
    JD.map fromRawPortMessage rawPortMessageDecoder


decodePortMessage : Value -> Result String PortMessage
decodePortMessage value =
    decodeValue portMessageDecoder value
