module Tests exposing (all)

import Dict
import Expect exposing (Expectation)
import Json.Decode as JD exposing (Decoder)
import Json.Encode as JE exposing (Value)
import List
import Maybe exposing (withDefault)
import Test exposing (..)
import WebSocketClient.PortMessage as PM
    exposing
        ( Continuation(..)
        , PortMessage(..)
        , RawPortMessage
        , decodePortMessage
        , encodePortMessage
        , encodeRawPortMessage
        )


testMap : (x -> String -> Test) -> List x -> List Test
testMap test data =
    let
        numbers =
            List.map String.fromInt <| List.range 1 (List.length data)
    in
    List.map2 test data numbers


oneAndTwo : ( a, b, c ) -> ( a, b )
oneAndTwo ( a, b, _ ) =
    ( a, b )


oneAndThree : ( a, b, c ) -> ( a, c )
oneAndThree ( a, _, c ) =
    ( a, c )


all : Test
all =
    Test.concat <|
        List.concat
            [ testMap toRawTest <| List.map oneAndTwo toRawData
            , testMap encodeRawTest <| List.map oneAndThree toRawData
            , testMap fromRawTest fromRawData
            , testMap decodeRawTest fromRawData
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


toRawTest : ( PortMessage, RawPortMessage ) -> String -> Test
toRawTest ( message, sb ) name =
    test ("toRawTest \"" ++ name ++ "\"")
        (\_ ->
            Expect.equal sb <| PM.toRawPortMessage message
        )


encodeRawTest : ( PortMessage, String ) -> String -> Test
encodeRawTest ( message, sb ) name =
    test ("encodeRawTest \"" ++ name ++ "\"")
        (\_ ->
            let
                value =
                    encodePortMessage message

                string =
                    JE.encode 0 value
            in
            Expect.equal sb string
        )


toRawData : List ( PortMessage, RawPortMessage, String )
toRawData =
    [ ( POOpen
            { key = "thekey"
            , url = "theurl"
            }
      , RawPortMessage "open" <|
            Dict.fromList
                [ ( "key", "thekey" )
                , ( "url", "theurl" )
                ]
      , "{\"tag\":\"open\",\"args\":{\"key\":\"thekey\",\"url\":\"theurl\"}}"
      )
    , ( POSend
            { key = "thekey"
            , message = "hello"
            }
      , RawPortMessage "send" <|
            Dict.fromList
                [ ( "key", "thekey" )
                , ( "message", "hello" )
                ]
      , "{\"tag\":\"send\",\"args\":{\"key\":\"thekey\",\"message\":\"hello\"}}"
      )
    , ( POClose
            { key = "anotherkey"
            , reason = "because"
            }
      , RawPortMessage "close" <|
            Dict.fromList
                [ ( "key", "anotherkey" )
                , ( "reason", "because" )
                ]
      , "{\"tag\":\"close\",\"args\":{\"key\":\"anotherkey\",\"reason\":\"because\"}}"
      )
    , ( POBytesQueued { key = "anotherkey" }
      , RawPortMessage "bytesQueued" <|
            Dict.fromList [ ( "key", "anotherkey" ) ]
      , "{\"tag\":\"bytesQueued\",\"args\":{\"key\":\"anotherkey\"}}"
      )
    , ( PODelay
            { millis = 20
            , id = "1"
            }
      , RawPortMessage "delay" <|
            Dict.fromList
                [ ( "millis", "20" )
                , ( "id", "1" )
                ]
      , "{\"tag\":\"delay\",\"args\":{\"id\":\"1\",\"millis\":\"20\"}}"
      )
    ]


fromRawTest : ( RawPortMessage, PortMessage ) -> String -> Test
fromRawTest ( message, sb ) name =
    test ("fromRawTest \"" ++ name ++ "\"")
        (\_ ->
            Expect.equal sb <| PM.fromRawPortMessage message
        )


decodeRawTest : ( RawPortMessage, PortMessage ) -> String -> Test
decodeRawTest ( rpm, sb ) name =
    let
        value =
            encodeRawPortMessage rpm
    in
    test ("decodeRawTest \"" ++ name ++ "\"")
        (\_ ->
            expectResult (Ok sb) <| PM.decodePortMessage value
        )


fromRawData : List ( RawPortMessage, PortMessage )
fromRawData =
    [ ( RawPortMessage "connected" <|
            Dict.fromList
                [ ( "key", "somekey" )
                , ( "description", "bloody fine" )
                ]
      , PIConnected
            { key = "somekey"
            , description = "bloody fine"
            }
      )
    , ( RawPortMessage "messageReceived" <|
            Dict.fromList
                [ ( "key", "somekey" )
                , ( "message", "Earth to Bob. Come in Bob" )
                ]
      , PIMessageReceived
            { key = "somekey"
            , message = "Earth to Bob. Come in Bob"
            }
      )
    , ( RawPortMessage "closed" <|
            Dict.fromList
                [ ( "key", "somekey" )
                , ( "code", "1000" )
                , ( "reason", "because we like you" )
                , ( "wasClean", "true" )
                ]
      , PIClosed
            { key = "somekey"
            , code = 1000 --normal close
            , reason = "because we like you"
            , wasClean = True
            }
      )
    , ( RawPortMessage "closed" <|
            Dict.fromList
                [ ( "key", "somekey" )
                , ( "code", "1006" )
                , ( "reason", "I had a bad day" )
                , ( "wasClean", "false" )
                ]
      , PIClosed
            { key = "somekey"
            , code = 1006 --abnormal closure
            , reason = "I had a bad day"
            , wasClean = False
            }
      )
    , ( RawPortMessage "bytesQueued" <|
            Dict.fromList
                [ ( "key", "somekey" )
                , ( "bufferedAmount", "12" )
                ]
      , PIBytesQueued
            { key = "somekey"
            , bufferedAmount = 12
            }
      )
    , ( RawPortMessage "bytesQueued" <|
            Dict.fromList
                [ ( "key", "somekey" )
                , ( "bufferedAmount", "23 skidoo" )
                ]
        -- illegal number for bufferedAmount
      , InvalidMessage
      )
    , ( RawPortMessage "delayed" <|
            Dict.fromList
                [ ( "id", "2" ) ]
      , PIDelayed { id = "2" }
      )
    , ( RawPortMessage "error" <|
            Dict.fromList
                [ ( "key", "somekey" )
                , ( "code", "green" )
                , ( "description", "You rock!" )
                , ( "name", "SecurityError" )
                ]
      , PIError
            { key = Just "somekey"
            , code = "green"
            , description = "You rock!"
            , name = Just "SecurityError"
            }
      )
    , ( RawPortMessage "error" <|
            Dict.fromList
                [ ( "key", "somekey" )
                , ( "code", "orange" )
                , ( "description", "Hit me with your best shot" )
                ]
      , PIError
            { key = Just "somekey"
            , code = "orange"
            , description = "Hit me with your best shot"
            , name = Nothing
            }
      )
    , ( RawPortMessage "error" <|
            Dict.fromList
                [ ( "code", "green" )
                , ( "description", "You rock!" )
                ]
      , PIError
            { key = Nothing
            , code = "green"
            , description = "You rock!"
            , name = Nothing
            }
      )
    , ( RawPortMessage "error2" <|
            Dict.fromList
                [ ( "code", "green" )
                , ( "description", "You rock!" )
                ]
        -- "error2" is not a known message
      , InvalidMessage
      )
    ]
