----------------------------------------------------------------------
--
-- WebSocketClient.elm
-- An Elm 0.19 package providing the old Websocket package functionality
-- using ports instead of a kernel module and effects manager.
-- Copyright (c) 2018 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE
--
----------------------------------------------------------------------


module WebSocketClient exposing
    ( Config, State, Response(..), Error(..), ClosedCode(..)
    , makeConfig, makeState
    , getKeyUrl, getConfig, setConfig
    , open, keepAlive, send, close, process
    , openWithKey, keepAliveWithKey
    , makeSimulatorConfig
    , errorToString, closedCodeToString
    )

{-| Web sockets make it cheaper to talk to your servers.

Connecting to a server takes some time, so with web sockets, you make that
connection once and then keep using. The major benefits of this are:

1.  It faster to send messages. No need to do a bunch of work for every single
    message.

2.  The server can push messages to you. With normal HTTP you would have to
    keep _asking_ for changes, but a web socket, the server can talk to you
    whenever it wants. This means there is less unnecessary network traffic.


# Web Sockets


## Types

@docs Config, State, Response, Error, ClosedCode


## State

@docs makeConfig, makeState
@docs getKeyUrl, getConfig, setConfig


## API

@docs open, keepAlive, send, close, process
@docs openWithKey, keepAliveWithKey


## Simulator

@docs makeSimulatorConfig


## Printing errors

@docs errorToString, closedCodeToString

-}

import Dict exposing (Dict)
import Json.Encode as JE exposing (Value)
import Process
import Set exposing (Set)
import Task exposing (Task)
import WebSocketClient.PortMessage
    exposing
        ( PortMessage(..)
        , decodePortMessage
        , encodePortMessage
        )



-- COMMANDS


{-| Send a message to a particular address. You might say something like this:

    send state "ws://echo.websocket.org" "Hello!"

You must call `open` or `openWithKey` before calling `send`.

-}
send : State msg -> String -> String -> ( State msg, Response msg )
send (State state) key message =
    if not (Set.member key state.openSockets) then
        ( State state, ErrorResponse <| SocketNotOpenError key )

    else
        let
            (Config { sendPort, simulator }) =
                state.config

            po =
                POSend { key = key, message = message }
        in
        case simulator of
            Nothing ->
                ( State state
                , CmdResponse <| sendPort (encodePortMessage po)
                )

            Just transformer ->
                ( State state
                , case transformer message of
                    Just response ->
                        MessageReceivedResponse
                            { key = key
                            , message = response
                            }

                    _ ->
                        NoResponse
                )



-- SUBSCRIPTIONS


{-| Subscribe to any incoming messages on a websocket. You might say something
like this:

    type Msg = Echo String | ...

    subscriptions model =
      open "ws://echo.websocket.org" Echo

**Note:** If the connection goes down, the effect manager tries to reconnect
with an exponential backoff strategy. Any messages you try to `send` while the
connection is down are queued and will be sent as soon as possible.

    open state url

-}
open : State msg -> String -> ( State msg, Response msg )
open state url =
    openWithKey state url url


{-| Like `open`, but allows matching a unique key to the connection.

`open` uses the url as the key.

    openWithKey state key url

-}
openWithKey : State msg -> String -> String -> ( State msg, Response msg )
openWithKey (State state) key url =
    case checkUsedSocket state key of
        Just res ->
            res

        Nothing ->
            let
                (Config { sendPort, simulator }) =
                    state.config

                po =
                    POOpen { key = key, url = url }
            in
            case simulator of
                Nothing ->
                    ( State
                        { state
                            | connectingSockets =
                                Set.insert key state.connectingSockets
                        }
                    , CmdResponse <| sendPort (encodePortMessage po)
                    )

                Just _ ->
                    ( State
                        { state
                            | openSockets =
                                Set.insert key state.openSockets
                        }
                    , ConnectedResponse
                        { key = key
                        , description = "simulated"
                        }
                    )


checkUsedSocket : StateRecord msg -> String -> Maybe ( State msg, Response msg )
checkUsedSocket state key =
    if Set.member key state.openSockets then
        Just ( State state, ErrorResponse <| SocketAlreadyOpenError key )

    else if Set.member key state.connectingSockets then
        Just ( State state, ErrorResponse <| SocketConnectingError key )

    else if Set.member key state.closingSockets then
        Just ( State state, ErrorResponse <| SocketClosingError key )

    else
        Nothing


{-| Close a WebSocket opened by `open` or `keepAlive`.

    close state key

The `key` arg is either they `key` arg to `openWithKey` or
`keepAliveWithKey` or the `url` arg to `open` or `keepAlive`.

-}
close : State msg -> String -> ( State msg, Response msg )
close (State state) key =
    let
        openSockets =
            state.openSockets

        closingSockets =
            state.closingSockets
    in
    if not (Set.member key openSockets) then
        ( State state, ErrorResponse <| SocketNotOpenError key )

    else
        let
            (Config { sendPort, simulator }) =
                state.config

            po =
                POClose { key = key, reason = "user request" }
        in
        case simulator of
            Nothing ->
                ( State
                    { state
                        | openSockets =
                            Set.remove key openSockets
                        , closingSockets =
                            Set.insert key closingSockets
                    }
                , CmdResponse <| sendPort (encodePortMessage po)
                )

            Just _ ->
                ( State
                    { state
                        | openSockets =
                            Set.remove key openSockets
                    }
                , ClosedResponse
                    { key = key
                    , code = NormalClosure
                    , reason = "simulator"
                    , wasClean = True
                    , expected = True
                    }
                )


{-| Keep a connection alive, but do not report any messages. This is useful
for keeping a connection open for when you only need to `send` messages. So
you might say something like this:

    let (state2, response) =
        keepAlive state "ws://echo.websocket.org"
    in
        ...

**Note:** If the connection goes down, the effect manager tries to reconnect
with an exponential backoff strategy. Any messages you try to `send` while the
connection is down are queued and will be sent as soon as possible.

-}
keepAlive : State msg -> String -> ( State msg, Response msg )
keepAlive state url =
    keepAliveWithKey state url url


{-| Like `keepAlive`, but allows matching a unique key to the connection.

    keeAliveWithKey state key url

-}
keepAliveWithKey : State msg -> String -> String -> ( State msg, Response msg )
keepAliveWithKey state key url =
    ( state
    , ErrorResponse <|
        UnimplementedError { function = "keepAliveWithKey" }
    )



-- MANAGER


type alias ConfigRecord msg =
    { sendPort : Value -> Cmd msg
    , simulator : Maybe (String -> Maybe String)
    }


{-| Packages up your ports to put inside a `State`.

Opaque type, created by `makeConfig`.

-}
type Config msg
    = Config (ConfigRecord msg)


{-| Make a real configuration, with your input and output ports.

The parameters are:

    makeConfig sendPort

Where `sendPort` is your output (`Cmd`) port.

Your input (`Sub`) port should wrap a `Json.Encode.Value` with a message,
and when your `update` function gets that message, it should pass it to
`process`, and then store the returned `State` in your model, and handle
the returned `Response`.

-}
makeConfig : (Value -> Cmd msg) -> Config msg
makeConfig sendPort =
    Config <| ConfigRecord sendPort Nothing


{-| Make a `Config` that enables running your code in `elm reactor`.

The arg is a server simulator, which translates a message sent with `send`
to a response.

-}
makeSimulatorConfig : (String -> Maybe String) -> Config msg
makeSimulatorConfig simulator =
    Config <| ConfigRecord (\_ -> Cmd.none) (Just simulator)


type alias QueuesDict =
    Dict.Dict String (List String)


type alias StateRecord msg =
    { config : Config msg
    , openSockets : Set String
    , connectingSockets : Set String
    , closingSockets : Set String
    , socketUrls : Dict String String
    , queues : QueuesDict
    }


{-| Internal state of the WebSocketClient module.

Create one with `makeState`, passed to most of the other functions.

-}
type State msg
    = State (StateRecord msg)


{-| Make state to store in your model.

The `Config` arg is the result of `makeConfig` or `makeSimulatorConfig`.

-}
makeState : Config msg -> State msg
makeState config =
    State <| StateRecord config Set.empty Set.empty Set.empty Dict.empty Dict.empty


{-| Get the URL for a key.
-}
getKeyUrl : String -> State msg -> Maybe String
getKeyUrl key (State state) =
    Dict.get key state.socketUrls


{-| Get a State's Config
-}
getConfig : State msg -> Config msg
getConfig (State state) =
    state.config


{-| Get a State's Config
-}
setConfig : Config msg -> State msg -> State msg
setConfig config (State state) =
    State { state | config = config }


{-| A response that your code must process to update your model.

`NoResponse` means there's nothing to do.

`CmdResponse` is a `Cmd` that you must return from your `update` function. It will send something out the `sendPort` in your `Config`.

`ConnectedReponse` tells you that an earlier call to `send` or `keepAlive` has successfully connected. You can usually ignore this.

`MessageReceivedResponse` is a message from one of the connected sockets.

`ClosedResponse` tells you that an earlier call to `close` has completed. Its `code`, `reason`, and `wasClean` fields are as passed by the JavaScript `WebSocket` interface. Its `expected` field will be `True`, if the response is to a `close` call on your part. It will be `False` if the close was unexpected. Unexpected closes will eventually be handled be trying to reconnect, but that isn't implemented yet.

`ErrorResponse` means that something went wrong. This will eventually have more structure. It is the raw data from the port code now.

-}
type Response msg
    = NoResponse
    | CmdResponse (Cmd msg)
    | ConnectedResponse { key : String, description : String }
    | MessageReceivedResponse { key : String, message : String }
    | ClosedResponse
        { key : String
        , code : ClosedCode
        , reason : String
        , wasClean : Bool
        , expected : Bool
        }
    | ErrorResponse Error


{-| All the errors that can be returned in a Response.ErrorResponse.

If an error tag has a single `String` arg, that string is a socket `key`.

-}
type Error
    = UnimplementedError { function : String }
    | SocketAlreadyOpenError String
    | SocketConnectingError String
    | SocketClosingError String
    | SocketNotOpenError String
    | PortDecodeError { error : String }
    | UnexpectedConnectedError { key : String, description : String }
    | UnexpectedMessageError { key : String, message : String }
    | LowLevelError
        { key : Maybe String
        , code : String
        , description : String
        , name : Maybe String
        }
    | InvalidMessageError { json : String }


{-| Convert an `Error` to a string, for simple reporting.
-}
errorToString : Error -> String
errorToString theError =
    case theError of
        UnimplementedError { function } ->
            "UnimplementedError { function = \"" ++ function ++ "\" }"

        SocketAlreadyOpenError key ->
            "SocketAlreadyOpenError \"" ++ key ++ "\""

        SocketConnectingError key ->
            "SocketConnectingError \"" ++ key ++ "\""

        SocketClosingError key ->
            "SocketClosingError \"" ++ key ++ "\""

        SocketNotOpenError key ->
            "SocketNotOpenError \"" ++ key ++ "\""

        PortDecodeError { error } ->
            "PortDecodeError { error = \"" ++ error ++ "\" }"

        UnexpectedConnectedError { key, description } ->
            "UnexpectedConnectedError\n { key = \""
                ++ key
                ++ "\", description = \""
                ++ description
                ++ "\" }"

        UnexpectedMessageError { key, message } ->
            "UnexpectedMessageError { key = \""
                ++ key
                ++ "\", message = \""
                ++ message
                ++ "\" }"

        LowLevelError { key, code, description, name } ->
            "LowLevelError { key = \""
                ++ maybeStringToString key
                ++ "\", code = \""
                ++ code
                ++ "\", description = \""
                ++ description
                ++ "\", code = \""
                ++ maybeStringToString name
                ++ "\" }"

        InvalidMessageError { json } ->
            json


maybeStringToString : Maybe String -> String
maybeStringToString string =
    case string of
        Nothing ->
            "Nothing"

        Just s ->
            "Just \"" ++ s ++ "\""


boolToString : Bool -> String
boolToString bool =
    if bool then
        "True"

    else
        "False"


{-| Process a Value that comes in over the subscription port.
-}
process : State msg -> Value -> ( State msg, Response msg )
process (State state) value =
    case decodePortMessage value of
        Err errstr ->
            ( State state
            , ErrorResponse <|
                PortDecodeError { error = errstr }
            )

        Ok pi ->
            let
                connectingSockets =
                    state.connectingSockets

                openSockets =
                    state.openSockets

                closingSockets =
                    state.closingSockets
            in
            case pi of
                PIConnected { key, description } ->
                    if not (Set.member key connectingSockets) then
                        -- TODO: close the unexpected connection
                        ( State state
                        , ErrorResponse <|
                            UnexpectedConnectedError
                                { key = key, description = description }
                        )

                    else
                        ( State
                            { state
                                | connectingSockets =
                                    Set.remove key connectingSockets
                                , openSockets =
                                    Set.insert key openSockets
                            }
                        , ConnectedResponse
                            { key = key, description = description }
                        )

                PIMessageReceived { key, message } ->
                    if not (Set.member key openSockets) then
                        ( State state
                        , ErrorResponse <|
                            UnexpectedMessageError
                                { key = key, message = message }
                        )

                    else
                        ( State state
                        , MessageReceivedResponse { key = key, message = message }
                        )

                PIClosed { key, code, reason, wasClean } ->
                    if not (Set.member key closingSockets) then
                        -- TODO: reopen or close the connection
                        ( State
                            { state
                                | connectingSockets =
                                    Set.remove key connectingSockets
                                , openSockets =
                                    Set.remove key openSockets
                                , closingSockets =
                                    Set.remove key closingSockets
                            }
                        , ClosedResponse
                            { key = key
                            , code = closedCode code
                            , reason = reason
                            , wasClean = wasClean
                            , expected = False
                            }
                        )

                    else
                        ( State
                            { state
                                | closingSockets =
                                    Set.remove key closingSockets
                            }
                        , ClosedResponse
                            { key = key
                            , code = closedCode code
                            , reason = reason
                            , wasClean = wasClean
                            , expected = True
                            }
                        )

                PIBytesQueued { key, bufferedAmount } ->
                    ( State state, NoResponse )

                PIError { key, code, description, name } ->
                    ( State state
                    , ErrorResponse <|
                        LowLevelError
                            { key = key
                            , code = code
                            , description = description
                            , name = name
                            }
                    )

                _ ->
                    ( State state
                    , ErrorResponse <|
                        InvalidMessageError
                            { json = JE.encode 0 value }
                    )


{-| <https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent>
-}
type ClosedCode
    = NormalClosure --1000
    | GoingAwayClosure --1002
    | ProtocolErrorClosure --1002
    | UnsupprtedDataClosure --1003
    | NoStatusRecvdClosure --1005
    | AbnormalClosure --1006
    | InvalidFramePayloadDataClosure --1007
    | PolicyViolationClosure --1008
    | MessageTooBigClosure --1009
    | MissingExtensionClosure --1010
    | InternalErrorClosure --1011
    | ServiceRestartClosure --1012
    | TryAgainLaterClosure --1013
    | BadGatewayClosure --1014
    | TLSHandshakeClosure --1015
    | UnknownClosure


closureDict : Dict Int ClosedCode
closureDict =
    Dict.fromList
        [ ( 1000, NormalClosure )
        , ( 1001, GoingAwayClosure )
        , ( 1002, ProtocolErrorClosure )
        , ( 1003, UnsupprtedDataClosure )
        , ( 1005, NoStatusRecvdClosure )
        , ( 1006, AbnormalClosure )
        , ( 1007, InvalidFramePayloadDataClosure )
        , ( 1008, PolicyViolationClosure )
        , ( 1009, MessageTooBigClosure )
        , ( 1010, MissingExtensionClosure )
        , ( 1011, InternalErrorClosure )
        , ( 1012, ServiceRestartClosure )
        , ( 1013, TryAgainLaterClosure )
        , ( 1014, BadGatewayClosure )
        , ( 1015, TLSHandshakeClosure )
        ]


closedCode : Int -> ClosedCode
closedCode code =
    case Dict.get code closureDict of
        Just res ->
            res

        Nothing ->
            UnknownClosure


closedCodeToString : ClosedCode -> String
closedCodeToString code =
    case code of
        NormalClosure ->
            "Normal"

        GoingAwayClosure ->
            "GoingAway"

        ProtocolErrorClosure ->
            "ProtocolError"

        UnsupprtedDataClosure ->
            "UnsupprtedData"

        NoStatusRecvdClosure ->
            "NoStatusRecvd"

        AbnormalClosure ->
            "Abnormal"

        InvalidFramePayloadDataClosure ->
            "InvalidFramePayloadData"

        PolicyViolationClosure ->
            "PolicyViolation"

        MessageTooBigClosure ->
            "MessageTooBig"

        MissingExtensionClosure ->
            "MissingExtension"

        InternalErrorClosure ->
            "InternalError"

        ServiceRestartClosure ->
            "ServiceRestart"

        TryAgainLaterClosure ->
            "TryAgainLater"

        BadGatewayClosure ->
            "BadGateway"

        TLSHandshakeClosure ->
            "TLSHandshake"

        UnknownClosure ->
            "UnknownClosureCode"



-- REOPEN LOST CONNECTIONS AUTOMATICALLY
-- May eventually contain some of the functionality in Effects.elm
