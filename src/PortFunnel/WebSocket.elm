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
    ( State, Response(..)
    , moduleName, moduleDesc, commander
    , initialState
    , send
    , isLoaded
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

@docs State, Response


## Components of a `PortFunnel.FunnelSpec`

@docs moduleName, moduleDesc, commander


## Initial `State`

@docs initialState


## Sending a `Message` out the `Cmd` Port

@docs send


## Non-standard functions

@docs isLoaded

-}

import Dict exposing (Dict)
import Json.Decode as JD exposing (Decoder)
import Json.Encode as JE exposing (Value)
import List.Extra as LE
import PortFunnel exposing (GenericMessage, ModuleDesc)
import PortFunnel.WebSocket.InternalMessage
    exposing
        ( InternalMessage(..)
        , PIClosedRecord
        )
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
    , keepalive : Bool
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
        }


{-| Returns true if a `Startup` message has been processed.

This is sent by the port code after it has initialized.

-}
isLoaded : State -> Bool
isLoaded (State state) =
    state.isLoaded


{-| `CmdResponse` denotes a message that needs to be sent through the port. This is done by the `commander` function.

`ListResponse` allows us to return multiple responses. `commander` descends a `ListResponse` looking for `CmdResponse` responses. `findMessages` descends a list of `Response` records, collecting the `MessageResponse` messages.

-}
type Response
    = NoResponse
    | CmdResponse Message
    | ListResponse (List Response)


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
            gm "open" <|
                JE.object
                    [ ( "key", JE.string key )
                    , ( "url", JE.string url )
                    ]

        POSend { key, message } ->
            gm "send" <|
                JE.object
                    [ ( "key", JE.string key )
                    , ( "message", JE.string message )
                    ]

        POClose { key, reason } ->
            gm "close" <|
                JE.object
                    [ ( "key", JE.string key )
                    , ( "reason", JE.string reason )
                    ]

        POBytesQueued { key } ->
            gm "bytesQueued" <|
                JE.object [ ( "key", JE.string key ) ]

        PODelay { millis, id } ->
            gm "delay" <|
                JE.object
                    [ ( "millis", JE.int millis )
                    , ( "id", JE.string id )
                    ]

        PIConnected { key, description } ->
            gm "connected" <|
                JE.object
                    [ ( "key", JE.string key )
                    , ( "description", JE.string description )
                    ]

        PIMessageReceived { key, message } ->
            gm "messageReceived" <|
                JE.object
                    [ ( "key", JE.string key )
                    , ( "message", JE.string message )
                    ]

        PIClosed { key, bytesQueued, code, reason, wasClean } ->
            gm "closed" <|
                JE.object
                    [ ( "key", JE.string key )
                    , ( "bytesQueued", JE.int bytesQueued )
                    , ( "code", JE.int code )
                    , ( "reason", JE.string reason )
                    , ( "wasClean", JE.bool wasClean )
                    ]

        PIBytesQueued { key, bufferedAmount } ->
            gm "bytesQueued" <|
                JE.object
                    [ ( "key", JE.string key )
                    , ( "bufferedAmount", JE.int bufferedAmount )
                    ]

        PIDelayed { id } ->
            gm "delayed" <|
                JE.object [ ( "id", JE.string id ) ]

        PIError { key, code, description, name } ->
            gm "error" <|
                JE.object
                    [ ( "key"
                      , case key of
                            Just k ->
                                JE.string k

                            Nothing ->
                                JE.null
                      )
                    , ( "code", JE.string code )
                    , ( "description", JE.string description )
                    , ( "name"
                      , case name of
                            Just n ->
                                JE.string n

                            Nothing ->
                                JE.null
                      )
                    ]


decode : GenericMessage -> Result String Message
decode { tag, args } =
    case tag of
        "startup" ->
            Ok Startup

        _ ->
            Err <| "Unknown Echo tag: " ++ tag


{-| Send a `Message` through a `Cmd` port.
-}
send : (Value -> Cmd msg) -> Message -> Cmd msg
send =
    PortFunnel.sendMessage moduleDesc


process : Message -> State -> ( State, Response )
process message ((State state) as unboxed) =
    case message of
        Startup ->
            ( State { state | isLoaded = True }
            , NoResponse
            )

        -- TODO
        _ ->
            ( unboxed, NoResponse )


{-| Responsible for sending a `CmdResponse` back througt the port.

Called by `PortFunnel.appProcess` for each response returned by `process`.

-}
commander : (GenericMessage -> Cmd msg) -> Response -> Cmd msg
commander gfPort response =
    case response of
        CmdResponse message ->
            encode message
                |> gfPort

        ListResponse messages ->
            List.foldl
                (\resp cmds ->
                    Cmd.batch
                        [ commander gfPort resp
                        , cmds
                        ]
                )
                Cmd.none
                messages

        _ ->
            Cmd.none



{-

   simulator : Message -> Maybe Message
   simulator message =
   case message of
   Request string ->
   Just (Request <| string ++ " (simulated)")

           Startup ->
               Nothing

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
   toString message =
   case message of
   Request string ->
   string

           Startup ->
               "<Startup>"

   {-| Convert a `Message` to the same JSON string that gets sent

   over the wire to the JS code.

   -}
   toJsonString : Message -> String
   toJsonString message =
   message
   |> encode
   |> PortFunnel.encodeGenericMessage
   |> JE.encode 0

   {-| Make a message to send out through the port.
   -}
   makeMessage : String -> Message
   makeMessage string =
   Request string

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
               List.append current [ message ]
       in
       ( State
           { state
               | queues = Dict.insert key new queues
           }
       , NoResponse
       )

   {-| Send a message to a particular address. You might say something like this:

       send state "ws://echo.websocket.org" "Hello!"

   You must call `open` or `openWithKey` before calling `send`.

   If you call `send` before the connection has been established, or while it is being reestablished after it was lost, your message will be buffered and sent after the connection has been (re)established.

       send state key message

   -}
   send : State msg -> String -> String -> ( State msg, Response msg )
   send (State state) key message =
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
         open "ws://echo.websocket.org" Echo

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
   openWithKey =
   openWithKeyInternal

   openWithKeyInternal : State msg -> String -> String -> ( State msg, Response msg )
   openWithKeyInternal (State state) key url =
   case checkUsedSocket state key of
   Err res ->
   res

           Ok socketState ->
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
                               | socketStates =
                                   Dict.insert key
                                       { socketState
                                           | phase = ConnectingPhase
                                           , url = url
                                       }
                                       state.socketStates
                           }
                       , CmdResponse <| sendPort (encodePortMessage po)
                       )

                   Just _ ->
                       ( State
                           { state
                               | socketStates =
                                   Dict.insert key
                                       { socketState
                                           | phase = ConnectedPhase
                                           , url = url
                                       }
                                       state.socketStates
                           }
                       , ConnectedResponse
                           { key = key
                           , description = "simulated"
                           }
                       )

   checkUsedSocket : StateRecord msg -> String -> Result ( State msg, Response msg ) SocketState
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

   {-| Close a WebSocket opened by `open` or `keepAlive`.

       close state key

   The `key` arg is either they `key` arg to `openWithKey` or
   `keepAliveWithKey` or the `url` arg to `open` or `keepAlive`.

   -}
   close : State msg -> String -> ( State msg, Response msg )
   close (State state) key =
   let
   socketState =
   getSocketState key state
   in
   if socketState.phase /= ConnectedPhase then
   -- TODO: cancel the callback if its in OpeningPhase with a backoff
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
             -- An abnormal close will be sent later
           , NoResponse
           )

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
                           | socketStates =
                               Dict.insert key
                                   { socketState | phase = ClosingPhase }
                                   state.socketStates
                       }
                   , CmdResponse <| sendPort (encodePortMessage po)
                   )

               Just _ ->
                   ( State
                       { state
                           | socketStates =
                               Dict.remove key state.socketStates
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

   -}
   keepAlive : State msg -> String -> ( State msg, Response msg )
   keepAlive state url =
   keepAliveWithKey state url url

   {-| Like `keepAlive`, but allows matching a unique key to the connection.

       keeAliveWithKey state key url

   -}
   keepAliveWithKey : State msg -> String -> String -> ( State msg, Response msg )
   keepAliveWithKey state key url =
   let
   ( State s, response ) =
   openWithKeyInternal state key url
   in
   case Dict.get key s.socketStates of
   Nothing ->
   ( State s, response )

           Just socketState ->
               ( State
                   { s
                       | socketStates =
                           Dict.insert key
                               { socketState | keepalive = True }
                               s.socketStates
                   }
               , response
               )

   -- MANAGER

   {-| Get the URL for a key.
   -}
   getKeyUrl : String -> State msg -> Maybe String
   getKeyUrl key (State state) =
   case Dict.get key state.socketStates of
   Just socketState ->
   Just socketState.url

           Nothing ->
               Nothing

   {-| Get a State's Config
   -}
   getConfig : State msg -> Config msg
   getConfig (State state) =
   state.config

   {-| Set a State's Config.

   Will likely break things if you do this while connections are active.

   -}
   setConfig : Config msg -> State msg -> State msg
   setConfig config (State state) =
   State { state | config = config }

   {-| A response that your code must process to update your model.

   `NoResponse` means there's nothing to do.

   `CmdResponse` is a `Cmd` that you must return from your `update` function. It will send something out the `sendPort` in your `Config`.

   `ConnectedReponse` tells you that an earlier call to `send` or `keepAlive` has successfully connected. You can usually ignore this.

   `MessageReceivedResponse` is a message from one of the connected sockets.

   `ClosedResponse` tells you that an earlier call to `close` has completed. Its `code`, `reason`, and `wasClean` fields are as passed by the JavaScript `WebSocket` interface. Its `expected` field will be `True`, if the response is to a `close` call on your part. It will be `False` if the close was unexpected, and reconnection attempts failed for 20 seconds (using exponential backoff between attempts).

   `ErrorResponse` means that something went wrong. Details in the encapsulated `Error`.

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
   "UnimplementedError { function = "" ++ function ++ "" }"

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

   getContinuation : String -> StateRecord msg -> Maybe ( String, ContinuationKind, StateRecord msg )
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

   allocateContinuation : String -> ContinuationKind -> StateRecord msg -> ( String, StateRecord msg )
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
                           , message = message
                           }

                   ( id, state2 ) =
                       allocateContinuation key DrainOutputQueue state

                   podelay =
                       PODelay
                           { millis = 20
                           , id = id
                           }

                   cmds =
                       Cmd.batch <|
                           List.map
                               (encodePortMessage >> sendPort)
                               [ podelay, posend ]
               in
               ( State
                   { state2
                       | queues =
                           Dict.insert key tail queues
                   }
               , CmdResponse cmds
               )

   emptySocketState : SocketState
   emptySocketState =
   { phase = IdlePhase
   , url = ""
   , backoff = 0
   , continuationId = Nothing
   , keepalive = False
   }

   getSocketState : String -> StateRecord msg -> SocketState
   getSocketState key state =
   Dict.get key state.socketStates
   |> Maybe.withDefault emptySocketState

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
               case pi of
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
                           , if socketState.keepalive then
                               NoResponse

                             else
                               MessageReceivedResponse { key = key, message = message }
                           )

                   PIClosed ({ key, code, reason, wasClean } as closedRecord) ->
                       let
                           socketStates =
                               getSocketState key state
                       in
                       if socketStates.phase /= ClosingPhase then
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
                               , expected = True
                               }
                           )

                   -- This needs to be queried when we get an unexpected
                   -- close, and if non-zero, then instead of reopening
                   -- tell the user about it.
                   PIBytesQueued { key, bufferedAmount } ->
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
                                           openWithKeyInternal
                                               (State
                                                   { state2
                                                       | socketStates =
                                                           Dict.insert key
                                                               { socketState
                                                                   | phase = IdlePhase
                                                               }
                                                               state.socketStates
                                                   }
                                               )
                                               key
                                               url

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
   case LE.find (( _, c ) -> c == code) closurePairs of
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
   10 \* (2 ^ backoff)

   handleUnexpectedClose : StateRecord msg -> PIClosedRecord -> ( State msg, Response msg )
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

       else
       -- It WAS successfully opened. Wait for the backoff time, and reopen.
       if
           socketState.url == ""
       then
           -- Shouldn't happen
           unexpectedClose state closedRecord

       else
           let
               ( id, state2 ) =
                   allocateContinuation key RetryConnection state

               delay =
                   PODelay
                       { millis =
                           backoffMillis backoff
                       , id = id
                       }
                       |> encodePortMessage

               (Config { sendPort }) =
                   state2.config
           in
           ( State
               { state2
                   | socketStates =
                       Dict.insert key
                           { socketState | backoff = backoff }
                           state.socketStates
               }
           , CmdResponse <| sendPort delay
           )

   unexpectedClose : StateRecord msg -> PIClosedRecord -> ( State msg, Response msg )
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

-}
