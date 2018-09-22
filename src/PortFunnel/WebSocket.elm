----------------------------------------------------------------------
--
-- WebSocket.elm
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
-- If `send` happens while in IdlePhase, open, send, close. Or not.
--


module PortFunnel.WebSocket exposing
    ( State, Message, Response(..), Error(..), ClosedCode(..)
    , moduleName, moduleDesc, commander
    , initialState
    , makeOpen, makeSend, makeClose
    , makeOpenWithKey, makeKeepAlive, makeKeepAliveWithKey
    , send
    , toString, toJsonString, errorToString, closedCodeToString
    , makeSimulatedCmdPort
    , isLoaded, isConnected, getKeyUrl, willAutoReopen, setAutoReopen
    , encode, decode
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

@docs State, Message, Response, Error, ClosedCode


## Components of a `PortFunnel.FunnelSpec`

@docs moduleName, moduleDesc, commander


## Initial `State`

@docs initialState


## Creating a `Message`

@docs makeOpen, makeSend, makeClose
@docs makeOpenWithKey, makeKeepAlive, makeKeepAliveWithKey


## Sending a `Message` out the `Cmd` Port

@docs send


# Conversion to Strings

@docs toString, toJsonString, errorToString, closedCodeToString


# Simulator

@docs makeSimulatedCmdPort


## Non-standard functions

@docs isLoaded, isConnected, getKeyUrl, willAutoReopen, setAutoReopen


## Internal, exposed only for tests

@docs encode, decode

-}

import Dict exposing (Dict)
import Json.Decode as JD exposing (Decoder)
import Json.Decode.Pipeline exposing (hardcoded, optional, required)
import Json.Encode as JE exposing (Value)
import List.Extra as LE
import PortFunnel exposing (GenericMessage, ModuleDesc)
import PortFunnel.WebSocket.InternalMessage
    exposing
        ( InternalMessage(..)
        , PIClosedRecord
        , PIErrorRecord
        )
import Set exposing (Set)
import Task exposing (Task)


type SocketPhase
    = IdlePhase
    | ConnectingPhase
    | ConnectedPhase
    | ClosingPhase


type alias SocketState =
    { phase : SocketPhase
    , url : String
    , backoff : Int
    , continuationId : Maybe String
    , keepAlive : Bool
    }


type ContinuationKind
    = RetryConnection
    | DrainOutputQueue


type alias Continuation =
    { key : String
    , kind : ContinuationKind
    }


type alias StateRecord =
    { isLoaded : Bool
    , socketStates : Dict String SocketState
    , continuationCounter : Int
    , continuations : Dict String Continuation
    , queues : Dict String (List String)
    , noAutoReopenKeys : Set String
    }


{-| Internal state of the WebSocketClient module.

Get the initial, empty state with `initialState`.

-}
type State
    = State StateRecord


{-| The initial, empty state.
-}
initialState : State
initialState =
    State
        { isLoaded = False
        , socketStates = Dict.empty
        , continuationCounter = 0
        , continuations = Dict.empty
        , queues = Dict.empty
        , noAutoReopenKeys = Set.empty
        }


{-| Returns true if a `Startup` message has been processed.

This is sent by the port code after it has initialized.

-}
isLoaded : State -> Bool
isLoaded (State state) =
    state.isLoaded


{-| Returns true if a connection is open for the given key.

    isConnected key state

-}
isConnected : String -> State -> Bool
isConnected key (State state) =
    Dict.get key state.socketStates /= Nothing


{-| Return `True` if the connection for the given key will be automatically reopened if it closes unexpectedly.

This is the default. You may change it with setAutoReopen.

    willAutoReopen key state

-}
willAutoReopen : String -> State -> Bool
willAutoReopen key (State state) =
    not <| Set.member key state.noAutoReopenKeys


{-| Set whether the connection for the given key will be automatically reopened if it closes unexpectedly.

This defaults to `True`. If you would rather get a `ClosedResponse` when it happens and handle it yourself, set it to `False` before sending a `makeOpen` message.

You may change it back to `False` later. Changing it to `True` later will not interrupt any ongoing reconnection process.

    setAutoReopen key autoReopen

The key is either the key you plan to use for a `makeOpenWithKey` or `makeKeepAliveWithKey` message or the url for a `makeOpen` or `makeKeepAlive` message.

-}
setAutoReopen : String -> Bool -> State -> State
setAutoReopen key autoReopen (State state) =
    let
        keys =
            if autoReopen then
                Set.remove key state.noAutoReopenKeys

            else
                Set.insert key state.noAutoReopenKeys
    in
    State { state | noAutoReopenKeys = keys }


{-| A response that your code must process to update your model.

`NoResponse` means there's nothing to do.

`CmdResponse` is a `Cmd` that you must return from your `update` function. It will send something out the `sendPort` in your `Config`.

`ConnectedReponse` tells you that an earlier call to `send` or `keepAlive` has successfully connected. You can usually ignore this.

`MessageReceivedResponse` is a message from one of the connected sockets.

`ClosedResponse` tells you that an earlier call to `close` has completed. Its `code`, `reason`, and `wasClean` fields are as passed by the JavaScript `WebSocket` interface. Its `expected` field will be `True`, if the response is to a `close` call on your part. It will be `False` if the close was unexpected, and reconnection attempts failed for 20 seconds (using exponential backoff between attempts).

`ErrorResponse` means that something went wrong. Details in the encapsulated `Error`.

-}
type Response
    = NoResponse
    | CmdResponse Message
    | ListResponse (List Response)
    | ConnectedResponse { key : String, description : String }
    | MessageReceivedResponse { key : String, message : String }
    | ClosedResponse
        { key : String
        , code : ClosedCode
        , reason : String
        , wasClean : Bool
        , expected : Bool
        }
    | BytesQueuedResponse { key : String, bufferedAmount : Int }
    | ErrorResponse Error


{-| Opaque message type.

You can create the instances you need to send with `openMessage`, `sendMessage`, `closeMessage`, and `bytesQueuedMessage`.

-}
type alias Message =
    InternalMessage


{-| The name of this module: "WebSocket".
-}
moduleName : String
moduleName =
    "WebSocket"


{-| Our module descriptor.
-}
moduleDesc : ModuleDesc Message State Response
moduleDesc =
    PortFunnel.makeModuleDesc moduleName encode decode process


{-| Encode a `Message` into a `GenericMessage`.

Only exposed so the tests can use it.

User code will use it implicitly through `moduleDesc`.

-}
encode : Message -> GenericMessage
encode mess =
    let
        gm tag args =
            GenericMessage moduleName tag args
    in
    case mess of
        Startup ->
            gm "startup" JE.null

        POOpen { key, url } ->
            JE.object
                [ ( "key", JE.string key )
                , ( "url", JE.string url )
                ]
                |> gm "open"

        POSend { key, message } ->
            JE.object
                [ ( "key", JE.string key )
                , ( "message", JE.string message )
                ]
                |> gm "send"

        POClose { key, reason } ->
            JE.object
                [ ( "key", JE.string key )
                , ( "reason", JE.string reason )
                ]
                |> gm "close"

        POBytesQueued { key } ->
            JE.object [ ( "key", JE.string key ) ]
                |> gm "getBytesQueued"

        PODelay { millis, id } ->
            JE.object
                [ ( "millis", JE.int millis )
                , ( "id", JE.string id )
                ]
                |> gm "delay"

        PWillOpen { key, url, keepAlive } ->
            JE.object
                [ ( "key", JE.string key )
                , ( "url", JE.string url )
                , ( "keepAlive", JE.bool keepAlive )
                ]
                |> gm "willopen"

        PWillSend { key, message } ->
            JE.object
                [ ( "key", JE.string key )
                , ( "message", JE.string message )
                ]
                |> gm "willsend"

        PWillClose { key, reason } ->
            JE.object
                [ ( "key", JE.string key )
                , ( "reason", JE.string reason )
                ]
                |> gm "willclose"

        PIConnected { key, description } ->
            JE.object
                [ ( "key", JE.string key )
                , ( "description", JE.string description )
                ]
                |> gm "connected"

        PIMessageReceived { key, message } ->
            JE.object
                [ ( "key", JE.string key )
                , ( "message", JE.string message )
                ]
                |> gm "messageReceived"

        PIClosed { key, bytesQueued, code, reason, wasClean } ->
            JE.object
                [ ( "key", JE.string key )
                , ( "bytesQueued", JE.int bytesQueued )
                , ( "code", JE.int code )
                , ( "reason", JE.string reason )
                , ( "wasClean", JE.bool wasClean )
                ]
                |> gm "closed"

        PIBytesQueued { key, bufferedAmount } ->
            JE.object
                [ ( "key", JE.string key )
                , ( "bufferedAmount", JE.int bufferedAmount )
                ]
                |> gm "bytesQueued"

        PIDelayed { id } ->
            JE.object [ ( "id", JE.string id ) ]
                |> gm "delayed"

        PIError { key, code, description, name, message } ->
            List.concat
                [ case key of
                    Just k ->
                        [ ( "key", JE.string k ) ]

                    Nothing ->
                        []
                , [ ( "code", JE.string code )
                  , ( "description", JE.string description )
                  ]
                , case name of
                    Just n ->
                        [ ( "name", JE.string n ) ]

                    Nothing ->
                        []
                , case message of
                    Just m ->
                        [ ( "message", JE.string m ) ]

                    Nothing ->
                        []
                ]
                |> JE.object
                |> gm "error"



--
-- A bunch of helper type aliases, to ease writing `decode` below.
--


type alias KeyUrl =
    { key : String, url : String }


type alias KeyUrlKeepAlive =
    { key : String, url : String, keepAlive : Bool }


type alias KeyMessage =
    { key : String, message : String }


type alias KeyReason =
    { key : String, reason : String }


type alias MillisId =
    { millis : Int, id : String }


type alias KeyDescription =
    { key : String, description : String }


type alias KeyBufferedAmount =
    { key : String, bufferedAmount : Int }


{-| This is basically `Json.Decode.decodeValue`,

but with the args reversed, and converting the error to a string.

-}
valueDecode : Value -> Decoder a -> Result String a
valueDecode value decoder =
    case JD.decodeValue decoder value of
        Ok a ->
            Ok a

        Err err ->
            Err <| JD.errorToString err


{-| Decode a `GenericMessage` into a `Message`.

Only exposed so the tests can use it.

User code will use it implicitly through `moduleDesc`.

-}
decode : GenericMessage -> Result String Message
decode { tag, args } =
    case tag of
        "startup" ->
            Ok Startup

        "open" ->
            JD.succeed KeyUrl
                |> required "key" JD.string
                |> required "url" JD.string
                |> JD.map POOpen
                |> valueDecode args

        "send" ->
            JD.succeed KeyMessage
                |> required "key" JD.string
                |> required "message" JD.string
                |> JD.map POSend
                |> valueDecode args

        "close" ->
            JD.succeed KeyReason
                |> required "key" JD.string
                |> required "reason" JD.string
                |> JD.map POClose
                |> valueDecode args

        "getBytesQueued" ->
            JD.succeed (\key -> { key = key })
                |> required "key" JD.string
                |> JD.map POBytesQueued
                |> valueDecode args

        "delay" ->
            JD.succeed MillisId
                |> required "millis" JD.int
                |> required "id" JD.string
                |> JD.map PODelay
                |> valueDecode args

        "willopen" ->
            JD.succeed KeyUrlKeepAlive
                |> required "key" JD.string
                |> required "url" JD.string
                |> required "keepAlive" JD.bool
                |> JD.map PWillOpen
                |> valueDecode args

        "willsend" ->
            JD.succeed KeyMessage
                |> required "key" JD.string
                |> required "message" JD.string
                |> JD.map PWillSend
                |> valueDecode args

        "willclose" ->
            JD.succeed KeyReason
                |> required "key" JD.string
                |> required "reason" JD.string
                |> JD.map PWillClose
                |> valueDecode args

        "connected" ->
            JD.succeed KeyDescription
                |> required "key" JD.string
                |> required "description" JD.string
                |> JD.map PIConnected
                |> valueDecode args

        "messageReceived" ->
            JD.succeed KeyMessage
                |> required "key" JD.string
                |> required "message" JD.string
                |> JD.map PIMessageReceived
                |> valueDecode args

        "closed" ->
            JD.succeed PIClosedRecord
                |> required "key" JD.string
                |> required "bytesQueued" JD.int
                |> required "code" JD.int
                |> required "reason" JD.string
                |> required "wasClean" JD.bool
                |> JD.map PIClosed
                |> valueDecode args

        "bytesQueued" ->
            JD.succeed KeyBufferedAmount
                |> required "key" JD.string
                |> required "bufferedAmount" JD.int
                |> JD.map PIBytesQueued
                |> valueDecode args

        "delayed" ->
            JD.succeed (\id -> { id = id })
                |> required "id" JD.string
                |> JD.map PIDelayed
                |> valueDecode args

        "error" ->
            JD.succeed PIErrorRecord
                |> optional "key" (JD.nullable JD.string) Nothing
                |> required "code" JD.string
                |> required "description" JD.string
                |> optional "name" (JD.nullable JD.string) Nothing
                |> optional "message" (JD.nullable JD.string) Nothing
                |> JD.map PIError
                |> valueDecode args

        _ ->
            Err <| "Unknown tag: " ++ tag


{-| Send a `Message` through a `Cmd` port.
-}
send : (Value -> Cmd msg) -> Message -> Cmd msg
send =
    PortFunnel.sendMessage moduleDesc


emptySocketState : SocketState
emptySocketState =
    { phase = IdlePhase
    , url = ""
    , backoff = 0
    , continuationId = Nothing
    , keepAlive = False
    }


getSocketState : String -> StateRecord -> SocketState
getSocketState key state =
    Dict.get key state.socketStates
        |> Maybe.withDefault emptySocketState


process : Message -> State -> ( State, Response )
process mess ((State state) as unboxed) =
    case mess of
        Startup ->
            ( State { state | isLoaded = True }
            , NoResponse
            )

        PWillOpen { key, url, keepAlive } ->
            doOpen state key url keepAlive

        PWillSend { key, message } ->
            doSend state key message

        PWillClose { key, reason } ->
            doClose state key reason

        PIConnected { key, description } ->
            let
                socketState =
                    getSocketState key state
            in
            if socketState.phase /= ConnectingPhase then
                ( State state
                , ErrorResponse <|
                    UnexpectedConnectedError
                        { key = key, description = description }
                )

            else
                let
                    newState =
                        { state
                            | socketStates =
                                Dict.insert key
                                    { socketState
                                        | phase = ConnectedPhase
                                        , backoff = 0
                                    }
                                    state.socketStates
                        }
                in
                if socketState.backoff == 0 then
                    ( State newState
                    , ConnectedResponse
                        { key = key, description = description }
                    )

                else
                    processQueuedMessage newState key

        PIMessageReceived { key, message } ->
            let
                socketState =
                    getSocketState key state
            in
            if socketState.phase /= ConnectedPhase then
                ( State state
                , ErrorResponse <|
                    UnexpectedMessageError
                        { key = key, message = message }
                )

            else
                ( State state
                , if socketState.keepAlive then
                    NoResponse

                  else
                    MessageReceivedResponse { key = key, message = message }
                )

        PIClosed ({ key, bytesQueued, code, reason, wasClean } as closedRecord) ->
            let
                socketState =
                    getSocketState key state

                expected =
                    socketState.phase == ClosingPhase
            in
            if not expected && not (Set.member key state.noAutoReopenKeys) then
                handleUnexpectedClose state closedRecord

            else
                ( State
                    { state
                        | socketStates =
                            Dict.remove key state.socketStates
                    }
                , ClosedResponse
                    { key = key
                    , code = closedCode code
                    , reason = reason
                    , wasClean = wasClean
                    , expected = expected
                    }
                )

        PIBytesQueued { key, bufferedAmount } ->
            -- TODO
            ( State state, NoResponse )

        PIDelayed { id } ->
            case getContinuation id state of
                Nothing ->
                    ( State state, NoResponse )

                Just ( key, kind, state2 ) ->
                    case kind of
                        DrainOutputQueue ->
                            processQueuedMessage state2 key

                        RetryConnection ->
                            let
                                socketState =
                                    getSocketState key state

                                url =
                                    socketState.url
                            in
                            if url /= "" then
                                ( State
                                    { state2
                                        | socketStates =
                                            Dict.insert key
                                                { socketState
                                                    | phase = ConnectingPhase
                                                }
                                                state.socketStates
                                    }
                                , CmdResponse <| POOpen { key = key, url = url }
                                )

                            else
                                -- This shouldn't be possible
                                unexpectedClose state
                                    { key = key
                                    , code =
                                        closedCodeNumber AbnormalClosure
                                    , bytesQueued = 0
                                    , reason =
                                        "Missing URL for reconnect"
                                    , wasClean =
                                        False
                                    }

        PIError { key, code, description, name, message } ->
            ( State state
            , ErrorResponse <|
                -- TODO.
                -- Can get an error on send or close while unexpected close retry.
                LowLevelError
                    { key = key
                    , code = code
                    , description = description
                    , name = name
                    , message = message
                    }
            )

        _ ->
            ( State state
            , ErrorResponse <|
                InvalidMessageError { message = mess }
            )


{-| All the errors that can be returned in a Response.ErrorResponse.

If an error tag has a single `String` arg, that string is a socket `key`.

-}
type Error
    = SocketAlreadyOpenError String
    | SocketConnectingError String
    | SocketClosingError String
    | SocketNotOpenError String
    | UnexpectedConnectedError { key : String, description : String }
    | UnexpectedMessageError { key : String, message : String }
    | LowLevelError PIErrorRecord
    | InvalidMessageError { message : Message }


{-| Convert an `Error` to a string, for simple reporting.
-}
errorToString : Error -> String
errorToString theError =
    case theError of
        SocketAlreadyOpenError key ->
            "SocketAlreadyOpenError \"" ++ key ++ "\""

        SocketConnectingError key ->
            "SocketConnectingError \"" ++ key ++ "\""

        SocketClosingError key ->
            "SocketClosingError \"" ++ key ++ "\""

        SocketNotOpenError key ->
            "SocketNotOpenError \"" ++ key ++ "\""

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

        InvalidMessageError { message } ->
            "InvalidMessageError: " ++ toString message


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


{-| Responsible for sending a `CmdResponse` back through the port.

Called by `PortFunnel.appProcess` for each response returned by `process`.

-}
commander : (GenericMessage -> Cmd msg) -> Response -> Cmd msg
commander gfPort response =
    case response of
        CmdResponse message ->
            encode message
                |> gfPort

        ListResponse responses ->
            List.foldl
                (\rsp res ->
                    case rsp of
                        CmdResponse message ->
                            message :: res

                        _ ->
                            res
                )
                []
                responses
                |> List.map (encode >> gfPort)
                |> Cmd.batch

        _ ->
            Cmd.none


simulator : Message -> Maybe Message
simulator mess =
    case mess of
        Startup ->
            Nothing

        PWillOpen record ->
            Just <| PWillOpen record

        POOpen { key } ->
            Just <|
                PIConnected { key = key, description = "Simulated connection." }

        PWillSend record ->
            Just <| PWillSend record

        POSend { key, message } ->
            Just <| PIMessageReceived { key = key, message = message }

        PWillClose record ->
            Just <| PWillClose record

        POClose { key, reason } ->
            Just <|
                PIClosed
                    { key = key
                    , bytesQueued = 0
                    , code = closedCodeNumber NormalClosure
                    , reason = "You asked for it, you got it, Toyota!"
                    , wasClean = True
                    }

        POBytesQueued { key } ->
            Just <| PIBytesQueued { key = key, bufferedAmount = 0 }

        PODelay { millis, id } ->
            Just <| PIDelayed { id = id }

        _ ->
            let
                name =
                    .tag <| encode mess
            in
            Just <|
                PIError
                    { key = Nothing
                    , code = "Unknown message"
                    , description = "You asked me to simulate an incoming message."
                    , name = Just name
                    , message = Nothing
                    }


{-| Make a simulated `Cmd` port.
-}
makeSimulatedCmdPort : (Value -> msg) -> Value -> Cmd msg
makeSimulatedCmdPort =
    PortFunnel.makeSimulatedFunnelCmdPort
        moduleDesc
        simulator


{-| Convert a `Message` to a nice-looking human-readable string.
-}
toString : Message -> String
toString mess =
    case mess of
        Startup ->
            "<Startup>"

        PWillOpen { key, url, keepAlive } ->
            "PWillOpen { key = \""
                ++ key
                ++ "\", url = \""
                ++ url
                ++ "\", keepAlive = "
                ++ (if keepAlive then
                        "True"

                    else
                        "False" ++ "}"
                   )

        POOpen { key, url } ->
            "POOpen { key = \"" ++ key ++ "\", url = \"" ++ url ++ "\"}"

        PIConnected { key, description } ->
            "PIConnected { key = \""
                ++ key
                ++ "\", description = \""
                ++ description
                ++ "\"}"

        PWillSend { key, message } ->
            "PWillSend { key = \"" ++ key ++ "\", message = \"" ++ message ++ "\"}"

        POSend { key, message } ->
            "POSend { key = \"" ++ key ++ "\", message = \"" ++ message ++ "\"}"

        PIMessageReceived { key, message } ->
            "PIMessageReceived { key = \""
                ++ key
                ++ "\", message = \""
                ++ message
                ++ "\"}"

        PWillClose { key, reason } ->
            "PWillClose { key = \"" ++ key ++ "\", reason = \"" ++ reason ++ "\"}"

        POClose { key, reason } ->
            "POClose { key = \"" ++ key ++ "\", reason = \"" ++ reason ++ "\"}"

        PIClosed { key, bytesQueued, code, reason, wasClean } ->
            "PIClosed { key = \""
                ++ key
                ++ "\", bytesQueued = \""
                ++ String.fromInt bytesQueued
                ++ "\", code = \""
                ++ String.fromInt code
                ++ "\", reason = \""
                ++ reason
                ++ "\", wasClean = \""
                ++ (if wasClean then
                        "True"

                    else
                        "False"
                            ++ "\"}"
                   )

        POBytesQueued { key } ->
            "POBytesQueued { key = \"" ++ key ++ "\"}"

        PIBytesQueued { key, bufferedAmount } ->
            "PIBytesQueued { key = \""
                ++ key
                ++ "\", bufferedAmount = \""
                ++ String.fromInt bufferedAmount
                ++ "\"}"

        PODelay { millis, id } ->
            "PODelay { millis = \""
                ++ String.fromInt millis
                ++ "\" id = \""
                ++ id
                ++ "\"}"

        PIDelayed { id } ->
            "PIDelayed { id = \"" ++ id ++ "\"}"

        PIError { key, code, description, name } ->
            "PIError { key = \""
                ++ maybeString key
                ++ "\" code = \""
                ++ code
                ++ "\" description = \""
                ++ description
                ++ "\" name = \""
                ++ maybeString name
                ++ "\"}"


maybeString : Maybe String -> String
maybeString s =
    case s of
        Nothing ->
            "Nothing"

        Just string ->
            "Just " ++ string


{-| Convert a `Message` to the same JSON string that gets sent

over the wire to the JS code.

-}
toJsonString : Message -> String
toJsonString message =
    message
        |> encode
        |> PortFunnel.encodeGenericMessage
        |> JE.encode 0


queueSend : StateRecord -> String -> String -> ( State, Response )
queueSend state key message =
    let
        queues =
            state.queues

        current =
            Dict.get key queues
                |> Maybe.withDefault []

        new =
            List.append current [ message ]
    in
    ( State
        { state
            | queues = Dict.insert key new queues
        }
    , NoResponse
    )



-- COMMANDS


{-| Create a `Message` to send a string to a particular address.

    makeSend key message

Example:

    makeSend "wss://echo.websocket.org" "Hello!"
        |> send cmdPort

You must send a `makeOpen` or `makeOpenWithKey` message before `makeSend`.

If you send a `makeSend` message before the connection has been established, or while it is being reestablished after it was lost, your message will be buffered and sent after the connection has been (re)established.

-}
makeSend : String -> String -> Message
makeSend key message =
    PWillSend { key = key, message = message }


doSend : StateRecord -> String -> String -> ( State, Response )
doSend state key message =
    let
        socketState =
            getSocketState key state
    in
    if socketState.phase /= ConnectedPhase then
        if socketState.backoff == 0 then
            -- TODO: This will eventually open, send, close.
            -- For now, though, it's an error.
            ( State state, ErrorResponse <| SocketNotOpenError key )

        else
            -- We're attempting to reopen the connection. Queue sends.
            queueSend state key message

    else if Dict.get key state.queues == Nothing then
        -- Normal send
        ( State state
        , CmdResponse <| POSend { key = key, message = message }
        )

    else
        -- We're queuing output. Add one more message to the queue.
        queueSend state key message


{-| Create a `Message` to open a connection to a WebSocket server.

    makeOpen url

Example:

    makeOpen "wss://echo.websocket.org"
        |> send cmdPort

-}
makeOpen : String -> Message
makeOpen url =
    makeOpenWithKey url url


{-| Like `makeOpen`, but allows matching a unique key to the connection.

`makeOpen` uses the url as the key.

    makeOpenWithKey key url

Example:

    makeOpenWithKey "echo" "wss://echo.websocket.org"

-}
makeOpenWithKey : String -> String -> Message
makeOpenWithKey key url =
    PWillOpen { key = key, url = url, keepAlive = False }


doOpen : StateRecord -> String -> String -> Bool -> ( State, Response )
doOpen state key url keepAlive =
    case checkUsedSocket state key of
        Err res ->
            res

        Ok socketState ->
            ( State
                { state
                    | socketStates =
                        Dict.insert key
                            { socketState
                                | phase = ConnectingPhase
                                , url = url
                                , keepAlive = keepAlive
                            }
                            state.socketStates
                }
            , CmdResponse <| POOpen { key = key, url = url }
            )


checkUsedSocket : StateRecord -> String -> Result ( State, Response ) SocketState
checkUsedSocket state key =
    let
        socketState =
            getSocketState key state
    in
    case socketState.phase of
        IdlePhase ->
            Ok socketState

        ConnectedPhase ->
            Err ( State state, ErrorResponse <| SocketAlreadyOpenError key )

        ConnectingPhase ->
            Err ( State state, ErrorResponse <| SocketConnectingError key )

        ClosingPhase ->
            Err ( State state, ErrorResponse <| SocketClosingError key )


{-| Create a `Message` to close a previously opened WebSocket.

    makeClose key

The `key` arg is either they `key` arg to `makeOpenWithKey` or
`makeKeepAliveWithKey` or the `url` arg to `makeOpen` or `makeKeepAlive`.

Example:

    makeClose "echo"
        |> send cmdPort

-}
makeClose : String -> Message
makeClose key =
    PWillClose { key = key, reason = "user request" }


doClose : StateRecord -> String -> String -> ( State, Response )
doClose state key reason =
    let
        socketState =
            getSocketState key state
    in
    if socketState.phase /= ConnectedPhase then
        ( State
            { state
                | continuations =
                    case socketState.continuationId of
                        Nothing ->
                            state.continuations

                        Just id ->
                            Dict.remove id state.continuations
                , socketStates =
                    Dict.remove key state.socketStates
            }
          -- An abnormal close error will be returned later
        , NoResponse
        )

    else
        ( State
            { state
                | socketStates =
                    Dict.insert key
                        { socketState | phase = ClosingPhase }
                        state.socketStates
            }
        , CmdResponse <| POClose { key = key, reason = "user request" }
        )


{-| Create a `Message` to connect to a WebSocket server, but not report received messages.

    makeKeepAlive url

For keeping a connection open for when you only need to send `makeSend` messages.

Example:

       makeKeepAlive "wss://echo.websocket.org"
         |> send cmdPort

-}
makeKeepAlive : String -> Message
makeKeepAlive url =
    makeKeepAliveWithKey url url


{-| Like `makeKeepAlive`, but allows matching a unique key to the connection.

       makeKeepAliveWithKey key url

Example:

       makeKeepAliveWithKey "echo" "wss://echo.websocket.org"
         |> send cmdPort

-}
makeKeepAliveWithKey : String -> String -> Message
makeKeepAliveWithKey key url =
    PWillOpen { key = key, url = url, keepAlive = True }



-- MANAGER


{-| Get the URL for a key.
-}
getKeyUrl : String -> State -> Maybe String
getKeyUrl key (State state) =
    case Dict.get key state.socketStates of
        Just socketState ->
            Just socketState.url

        Nothing ->
            Nothing


getContinuation : String -> StateRecord -> Maybe ( String, ContinuationKind, StateRecord )
getContinuation id state =
    case Dict.get id state.continuations of
        Nothing ->
            Nothing

        Just continuation ->
            Just
                ( continuation.key
                , continuation.kind
                , { state
                    | continuations = Dict.remove id state.continuations
                  }
                )


allocateContinuation : String -> ContinuationKind -> StateRecord -> ( String, StateRecord )
allocateContinuation key kind state =
    let
        counter =
            state.continuationCounter + 1

        id =
            String.fromInt counter

        continuation =
            { key = key, kind = kind }

        ( continuations, socketState ) =
            case Dict.get key state.socketStates of
                Nothing ->
                    ( state.continuations, getSocketState key state )

                Just sockState ->
                    case sockState.continuationId of
                        Nothing ->
                            ( state.continuations
                            , { sockState
                                | continuationId = Just id
                              }
                            )

                        Just oldid ->
                            ( Dict.remove oldid state.continuations
                            , { sockState
                                | continuationId = Just id
                              }
                            )
    in
    ( id
    , { state
        | continuationCounter = counter
        , socketStates = Dict.insert key socketState state.socketStates
        , continuations = Dict.insert id continuation continuations
      }
    )


processQueuedMessage : StateRecord -> String -> ( State, Response )
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
                posend =
                    POSend
                        { key = key
                        , message = message
                        }

                ( id, state2 ) =
                    allocateContinuation key DrainOutputQueue state

                podelay =
                    PODelay
                        { millis = 20
                        , id = id
                        }

                response =
                    ListResponse
                        [ CmdResponse podelay
                        , CmdResponse posend
                        ]
            in
            ( State
                { state2
                    | queues =
                        Dict.insert key tail queues
                }
            , response
            )


{-| This will usually be `NormalClosure`. The rest are standard, except for `UnknownClosure`, which denotes a code that is not defined, and `TimeoutOutOnReconnect`, which means that exponential backoff connection reestablishment attempts timed out.

The standard codes are from <https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent>

-}
type ClosedCode
    = NormalClosure --1000
    | GoingAwayClosure --1002
    | ProtocolErrorClosure --1002
    | UnsupportedDataClosure --1003
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
    , ( 1003, UnsupportedDataClosure )
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

        -- Can't happen
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

        UnsupportedDataClosure ->
            "UnsupportedData"

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


handleUnexpectedClose : StateRecord -> PIClosedRecord -> ( State, Response )
handleUnexpectedClose state closedRecord =
    let
        key =
            closedRecord.key

        socketState =
            getSocketState key state

        backoff =
            1 + socketState.backoff
    in
    if
        (backoff > maxBackoff)
            || (backoff == 1 && socketState.phase /= ConnectedPhase)
            || (closedRecord.bytesQueued > 0)
    then
        -- It was never successfully opened
        -- or it was closed with output left unsent.
        unexpectedClose state
            { closedRecord
                | code =
                    if backoff > maxBackoff then
                        closedCodeNumber TimedOutOnReconnect

                    else
                        closedRecord.code
            }

    else if socketState.url == "" then
        -- Shouldn't happen
        unexpectedClose state closedRecord

    else
        -- It WAS successfully opened. Wait for the backoff time, and reopen.
        let
            ( id, state2 ) =
                allocateContinuation key RetryConnection state

            delay =
                PODelay
                    { millis =
                        backoffMillis backoff
                    , id = id
                    }
        in
        ( State
            { state2
                | socketStates =
                    Dict.insert key
                        { socketState | backoff = backoff }
                        state.socketStates
            }
        , CmdResponse delay
        )


unexpectedClose : StateRecord -> PIClosedRecord -> ( State, Response )
unexpectedClose state { key, code, reason, wasClean } =
    ( State
        { state
            | socketStates = Dict.remove key state.socketStates
        }
    , ClosedResponse
        { key = key
        , code = closedCode code
        , reason = reason
        , wasClean = wasClean
        , expected = False
        }
    )
