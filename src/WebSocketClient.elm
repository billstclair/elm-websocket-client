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
    ( Config, State
    , listen, keepAlive, send
    , close, keepAliveWithKey, listenWithKey, process, sendWithKey
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

@docs Config, State

@docs listen, keepAlive, send

-}

import Dict exposing (Dict)
import Json.Encode as JE exposing (Value)
import Process
import Set exposing (Set)
import Task exposing (Task)
import WebSocketClient.LowLevel as WS
import WebSocketClient.PortMessage
    exposing
        ( PortMessage(..)
        , decodePortMessage
        , encodePortMessage
        )



-- COMMANDS


{-| Send a message to a particular address. You might say something like this:

    send config state "ws://echo.websocket.org" "Hello!"

**Note:** It is important that you are also subscribed to this address with
`listen` or `keepAlive`. If you are not, the web socket will be created to
send one message and then closed. Not good!

-}
send : Config msg -> State msg -> String -> String -> ( State msg, Response msg )
send config state url message =
    sendWithKey config state url url message


{-| Like `send`, but allows matching a unique key to the connection.

`send` uses the `url` as the `key`.

    sendWithKey config state key url message

-}
sendWithKey : Config msg -> State msg -> String -> String -> String -> ( State msg, Response msg )
sendWithKey config state key url message =
    ( state, NoResponse )



-- SUBSCRIPTIONS


{-| Subscribe to any incoming messages on a websocket. You might say something
like this:

    type Msg = Echo String | ...

    subscriptions model =
      listen "ws://echo.websocket.org" Echo

**Note:** If the connection goes down, the effect manager tries to reconnect
with an exponential backoff strategy. Any messages you try to `send` while the
connection is down are queued and will be sent as soon as possible.

    listen config state url

-}
listen : Config msg -> State msg -> String -> ( State msg, Response msg )
listen config state url =
    listenWithKey config state url url


{-| Like `listen`, but allows matching a unique key to the connection.

`listen` uses the url as the key.

    listenWithKey config state key url

-}
listenWithKey : Config msg -> State msg -> String -> String -> ( State msg, Response msg )
listenWithKey config state key url =
    ( state, NoResponse )


{-| Close a WebSocket opened by `listen` or `keepAlive`.

    close config state key

The `key` arg is either they `key` arg to `listenWithKey` or
`keepAliveWithKey` or the `url` arg to `listen` or `keepAlive`.

-}
close : Config msg -> State msg -> String -> ( State msg, Response msg )
close config state key =
    ( state, NoResponse )


{-| Keep a connection alive, but do not report any messages. This is useful
for keeping a connection open for when you only need to `send` messages. So
you might say something like this:

    let (state2, response) =
        keepAlive config state "ws://echo.websocket.org"
    in
        ...

**Note:** If the connection goes down, the effect manager tries to reconnect
with an exponential backoff strategy. Any messages you try to `send` while the
connection is down are queued and will be sent as soon as possible.

-}
keepAlive : Config msg -> State msg -> String -> ( State msg, Response msg )
keepAlive config state url =
    keepAliveWithKey config state url url


{-| Like `keepAlive`, but allows matching a unique key to the connection.

    keeAliveWithKey config state key url

-}
keepAliveWithKey : Config msg -> State msg -> String -> String -> ( State msg, Response msg )
keepAliveWithKey config state key url =
    ( state, NoResponse )



-- MANAGER


type alias Config msg =
    { sendPort : Value -> Cmd msg
    , receivePort : (Value -> msg) -> Sub msg
    , simulator : Maybe (String -> String)
    }


{-| Make a real configuration, with your input and output ports.

The parameters are:

    makeConfig sendPort receivePort

Where `sendPort` is your output (`Cmd`) port, and `receivePort` is your input (`Sub`) port.

-}
makeConfig : (Value -> Cmd msg) -> ((Value -> msg) -> Sub msg) -> Config msg
makeConfig sendPort receivePort =
    Config sendPort receivePort Nothing


makeSimulatorConfig : (String -> String) -> Config msg
makeSimulatorConfig simulator =
    Config (\_ -> Cmd.none) (\_ -> Sub.none) (Just simulator)


type alias QueuesDict =
    Dict.Dict String (List String)


type alias StateRecord msg =
    { config : Config msg
    , openSockets : Set String
    , connectingSockets : Set String
    , queues : QueuesDict
    }


type State msg
    = State (StateRecord msg)


{-| Make state to store in your model.

The `Config` arg is the result of `makeConfig` or `makeSimulatorConfig`.

-}
makeState : Config msg -> State msg
makeState config =
    State <| StateRecord config Set.empty Set.empty Dict.empty


type Response msg
    = NoResponse
    | CmdResponse (Cmd msg)
    | ConnectedResponse { key : String }
    | MessageReceivedResponse { key : String, message : String }
    | ClosedResponse
        { key : String
        , code : String
        , reason : String
        , wasClean : Bool
        }
    | BytesQueuedResponse { key : String, bufferedAmount : Int }
    | ErrorResponse
        { key : Maybe String
        , code : String
        , description : String
        , name : Maybe String
        }


{-| Process a Value that comes in over the subscription port
-}
process : Config msg -> Value -> State msg -> ( State msg, Response msg )
process config value state =
    ( state, NoResponse )



-- HANDLE APP MESSAGES
-- Will eventually contain the functionality in Effects.elm
