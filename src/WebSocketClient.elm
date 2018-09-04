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
--
-- TODO
--
-- Move the Continuation into a table on the Elm side.
-- Just send a delay identifier to the JS code in `PODelay`.
-- If `PIDelayed` comes back with an unknown identifier, ignore it.
-- Must remove the identifier -> Continuation entry at
-- the appropriate times (connection reestablished, user closes connection).
--
-- If the connection goes down, don't try to restore it if there
-- are bytes queued in the JS. The user code will have to recover
-- in this case.
--


module WebSocketClient exposing
    ( PortVersion(..), Config, State, Response(..), Error(..), ClosedCode(..)
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

@docs PortVersion, Config, State, Response, Error, ClosedCode


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
import List.Extra as LE
import Process
import Set exposing (Set)
import Task exposing (Task)
import WebSocketClient.PortMessage
    exposing
        ( Continuation(..)
        , PIClosedRecord
        , PortMessage(..)
        , decodePortMessage
        , encodePortMessage
        )



-- COMMANDS


queueSend : StateRecord msg -> String -> String -> ( State msg, Response msg )
queueSend state key message =
    let
        queues =
            state.queues

        current =
            Dict.get key queues
                |> Maybe.withDefault []

        new =
            List.append current [ Debug.log "Queueing:" message ]
    in
    ( State
        { state
            | queues = Dict.insert key new queues
        }
    , NoResponse
    )


{-| Send a message to a particular address. You might say something like this:

    send PortVersion2 state "ws://echo.websocket.org" "Hello!"

You must call `open` or `openWithKey` before calling `send`.

The first arg is a `PortVersion`, to remind you to update your JavaScript
port code, when it changes incompatibly.

    send PortVersion2 state key message

-}
send : PortVersion -> State msg -> String -> String -> ( State msg, Response msg )
send _ (State state) key message =
    if not (Set.member key state.openSockets) then
        if Dict.get key state.socketBackoffs == Nothing then
            -- TODO: This will eventually open, send, close.
            -- For now, though, it's an error.
            ( State state, ErrorResponse <| SocketNotOpenError key )

        else
            -- We're attempting to reopen the connection. Queue sends.
            queueSend state key message

    else
        let
            (Config { sendPort, simulator }) =
                state.config

            po =
                POSend { key = key, message = message }
        in
        case simulator of
            Nothing ->
                if Dict.get key state.queues == Nothing then
                    -- Normal send through the `Cmd` port.
                    ( State state
                    , CmdResponse <| sendPort (encodePortMessage po)
                    )

                else
                    -- We're queuing output. Add one more message to the queue.
                    queueSend state key message

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
      open PortVersion2 "ws://echo.websocket.org" Echo

The first arg is a `PortVersion`, to remind you to update your JavaScript
port code, when it changes incompatibly.

    open PortVersion2 state url

-}
open : PortVersion -> State msg -> String -> ( State msg, Response msg )
open version state url =
    openWithKey version state url url


{-| Like `open`, but allows matching a unique key to the connection.

`open` uses the url as the key.

    openWithKey PortVersion2 state key url

-}
openWithKey : PortVersion -> State msg -> String -> String -> ( State msg, Response msg )
openWithKey _ =
    openWithKeyInternal


openWithKeyInternal : State msg -> String -> String -> ( State msg, Response msg )
openWithKeyInternal (State state) key url =
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
                            , socketUrls =
                                Dict.insert key url state.socketUrls
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


{-| A custom type with one tag.

The tag encodes the version of the port JavaScript code.
It changes every time that code changes incompatibly, to remind
you that you need to update it, and change your `open`, `openWithKey`,
and `send` calls accordingly.

-}
type PortVersion
    = PortVersion2


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
    , socketBackoffs : Dict String Int
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
    State <|
        StateRecord config
            -- openSockets
            Set.empty
            -- connectingSockets
            Set.empty
            -- closingSockets
            Set.empty
            -- socketUrls
            Dict.empty
            -- socketBackoffs
            Dict.empty
            -- queues
            Dict.empty


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


processQueuedMessage : StateRecord msg -> String -> ( State msg, Response msg )
processQueuedMessage state key =
    let
        queues =
            state.queues
    in
    case Dict.get key queues of
        Nothing ->
            ( State state, NoResponse )

        Just [] ->
            ( State
                { state
                    | queues = Dict.remove key queues
                }
            , NoResponse
            )

        Just (message :: tail) ->
            let
                (Config { sendPort }) =
                    state.config

                posend =
                    POSend
                        { key = key
                        , message =
                            Debug.log "Dequeuing:" message
                        }

                podelay =
                    PODelay
                        { millis = 20
                        , continuation =
                            DrainOutputQueue key
                        }

                cmds =
                    Cmd.batch <|
                        List.map
                            (encodePortMessage >> sendPort)
                            [ podelay, posend ]
            in
            ( State
                { state
                    | queues =
                        Dict.insert key tail queues
                }
            , CmdResponse cmds
            )


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
                        ( State state
                        , ErrorResponse <|
                            UnexpectedConnectedError
                                { key = key, description = description }
                        )

                    else
                        let
                            backoffs =
                                state.socketBackoffs

                            maybeBackoff =
                                Dict.get key backoffs

                            newState =
                                { state
                                    | connectingSockets =
                                        Set.remove key connectingSockets
                                    , openSockets =
                                        Set.insert key openSockets
                                    , socketBackoffs =
                                        Dict.remove key backoffs
                                }
                        in
                        if maybeBackoff == Nothing then
                            ( State newState
                            , ConnectedResponse
                                { key = key, description = description }
                            )

                        else
                            processQueuedMessage newState key

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

                PIClosed ({ key, code, reason, wasClean } as closedRecord) ->
                    if not (Set.member key closingSockets) then
                        handleUnexpectedClose state closedRecord

                    else
                        ( State
                            { state
                                | closingSockets =
                                    Set.remove key closingSockets
                                , socketUrls =
                                    Dict.remove key state.socketUrls
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

                PIDelayed { continuation } ->
                    case continuation of
                        RetryConnection key ->
                            case Dict.get key state.socketUrls of
                                Just url ->
                                    openWithKeyInternal
                                        (State
                                            { state
                                                | openSockets =
                                                    Set.remove key openSockets
                                                , connectingSockets =
                                                    Set.remove key connectingSockets
                                            }
                                        )
                                        key
                                        url

                                Nothing ->
                                    unexpectedClose state
                                        { key = key
                                        , code = closedCodeNumber AbnormalClosure
                                        , reason = "Missing URL for reconnect"
                                        , wasClean = False
                                        }

                        DrainOutputQueue key ->
                            let
                                queues =
                                    state.queues
                            in
                            processQueuedMessage state key

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
    | TimedOutOnReconnect -- 4000 (available for use by applications)
    | UnknownClosure


closurePairs : List ( Int, ClosedCode )
closurePairs =
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
    , ( 4000, TimedOutOnReconnect )
    ]


closureDict : Dict Int ClosedCode
closureDict =
    Dict.fromList closurePairs


closedCodeNumber : ClosedCode -> Int
closedCodeNumber code =
    case LE.find (\( _, c ) -> c == code) closurePairs of
        Just ( int, _ ) ->
            int

        Nothing ->
            0


closedCode : Int -> ClosedCode
closedCode code =
    Maybe.withDefault UnknownClosure <| Dict.get code closureDict


{-| Turn a `ClosedCode` into a `String`, for debugging.
-}
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

        TimedOutOnReconnect ->
            "TimedOutOnReconnect"

        UnknownClosure ->
            "UnknownClosureCode"



-- REOPEN LOST CONNECTIONS AUTOMATICALLY


{-| 10 x 1024 milliseconds = 10.2 seconds
-}
maxBackoff : Int
maxBackoff =
    10


backoffMillis : Int -> Int
backoffMillis backoff =
    10 * (2 ^ backoff)


handleUnexpectedClose : StateRecord msg -> PIClosedRecord -> ( State msg, Response msg )
handleUnexpectedClose state closedRecord =
    let
        key =
            closedRecord.key

        backoffs =
            state.socketBackoffs

        backoff =
            1 + Maybe.withDefault 0 (Dict.get key backoffs)
    in
    if
        (backoff > maxBackoff)
            || (backoff == 1 && (not <| Set.member key state.openSockets))
    then
        -- It was never successfully opened.
        unexpectedClose state
            { closedRecord
                | code =
                    if backoff > maxBackoff then
                        closedCodeNumber TimedOutOnReconnect

                    else
                        closedRecord.code
            }

    else
        -- It WAS successfully opened. Wait for the backoff time, and reopen.
        case Dict.get key state.socketUrls of
            Nothing ->
                unexpectedClose state closedRecord

            Just _ ->
                let
                    delay =
                        PODelay
                            { millis =
                                backoffMillis <|
                                    Debug.log "Backoff" backoff
                            , continuation =
                                RetryConnection key
                            }
                            |> encodePortMessage

                    (Config { sendPort }) =
                        state.config
                in
                ( State
                    { state
                        | socketBackoffs =
                            Dict.insert key backoff backoffs
                    }
                , CmdResponse <| sendPort delay
                )


unexpectedClose : StateRecord msg -> PIClosedRecord -> ( State msg, Response msg )
unexpectedClose state { key, code, reason, wasClean } =
    ( State
        { state
            | connectingSockets =
                Set.remove key state.connectingSockets
            , openSockets =
                Set.remove key state.openSockets
            , closingSockets =
                Set.remove key state.closingSockets
            , socketUrls =
                Dict.remove key state.socketUrls
        }
    , ClosedResponse
        { key = key
        , code = closedCode code
        , reason = reason
        , wasClean = wasClean
        , expected = False
        }
    )
