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
    ( PortMessage(..)
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


decodeRawPortMessage : Value -> Result String RawPortMessage
decodeRawPortMessage value =
    decodeValue rawPortMessageDecoder value


type PortMessage
    = InvalidMessage
      -- output
    | POOpen { key : String, url : String }
    | POSend { key : String, message : String }
    | POClose { key : String, reason : String }
    | POBytesQueued { key : String }
      -- input
    | PIConnected { key : String, description : String }
    | PIMessageReceived { key : String, message : String }
    | PIClosed { key : String, code : String, reason : String, wasClean : Bool }
    | PIBytesQueued { key : String, bufferedAmount : Int }
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
                        , code = code
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
