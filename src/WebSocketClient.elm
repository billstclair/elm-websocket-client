module WebSocketClient exposing
    ( Config, State, WebSocketCmd
    , listen, keepAlive, send
    )

{-| Web sockets make it cheaper to talk to your servers.

Connecting to a server takes some time, so with web sockets, you make that
connection once and then keep using. The major benefits of this are:

1.  It faster to send messages. No need to do a bunch of work for every single
    message.

2.  The server can push messages to you. With normal HTTP you would have to
    keep _asking_ for changes, but a web socket, the server can talk to you
    whenever it wants. This means there is less unnecessary network traffic.

The API here attempts to cover the typical usage scenarios, but if you need
many unique connections to the same endpoint, you need a different library.


# Web Sockets

@docs Config, State, WebSocketCmd

@docs listen, keepAlive, send

-}

import Dict
import Json.Encode exposing (Value)
import Process
import Task exposing (Task)
import WebSocketClient.LowLevel as WS



-- COMMANDS


{-| A command to pass, with a `State` to `processCmd`.
-}
type WebSocketCmd msg
    = Send String String


{-| Send a message to a particular address. You might say something like this:

    send "ws://echo.websocket.org" "Hello!"

**Note:** It is important that you are also subscribed to this address with
`listen` or `keepAlive`. If you are not, the web socket will be created to
send one message and then closed. Not good!

-}
send : String -> String -> Cmd msg
send url message =
    Cmd.none


cmdMap : (a -> b) -> WebSocketCmd a -> WebSocketCmd b
cmdMap _ (Send url msg) =
    Send url msg



-- SUBSCRIPTIONS


type MySub msg
    = Listen String (String -> msg)
    | KeepAlive String


{-| Subscribe to any incoming messages on a websocket. You might say something
like this:

    type Msg = Echo String | ...

    subscriptions model =
      listen "ws://echo.websocket.org" Echo

**Note:** If the connection goes down, the effect manager tries to reconnect
with an exponential backoff strategy. Any messages you try to `send` while the
connection is down are queued and will be sent as soon as possible.

-}
listen : String -> (String -> msg) -> Sub msg
listen url tagger =
    Sub.none


{-| Keep a connection alive, but do not report any messages. This is useful
for keeping a connection open for when you only need to `send` messages. So
you might say something like this:

    subscriptions model =
        keepAlive "ws://echo.websocket.org"

**Note:** If the connection goes down, the effect manager tries to reconnect
with an exponential backoff strategy. Any messages you try to `send` while the
connection is down are queued and will be sent as soon as possible.

-}
keepAlive : String -> Sub msg
keepAlive url =
    Sub.none


subMap : (a -> b) -> MySub a -> MySub b
subMap func sub =
    case sub of
        Listen url tagger ->
            Listen url (tagger >> func)

        KeepAlive url ->
            KeepAlive url



-- MANAGER


type alias Config msg =
    { wrapper : WebSocketCmd msg -> msg
    , sendPort : Value -> Cmd msg
    , receivePort : (Value -> msg) -> Sub msg
    , simulator : Maybe (String -> String)
    }


{-| Make a real configuration, with your input and output ports.

The parameters are:

    makeConfig wrapper sendPort receivePort

Where `wrapper` turns a `WebSocketCmd` into your `msg` type, sendPort is an output port, and receivePort is an input port.

-}
makeConfig : (WebSocketCmd msg -> msg) -> (Value -> Cmd msg) -> ((Value -> msg) -> Sub msg) -> Config msg
makeConfig wrapper sendPort receivePort =
    Config wrapper sendPort receivePort Nothing


makeSimulatorConfig : (WebSocketCmd msg -> msg) -> (String -> String) -> Config msg
makeSimulatorConfig wrapper simulator =
    Config wrapper (\_ -> Cmd.none) (\_ -> Sub.none) (Just simulator)


type alias StateRecord msg =
    { config : Config msg
    , sockets : SocketsDict
    , queues : QueuesDict
    , subs : SubsDict msg
    }


type State msg
    = State (StateRecord msg)


{-| Make state to store in your model.

The `Config` arg is the result of `makeConfig` or `makeSimulatorConfig`.

-}
makeState : Config msg -> State msg
makeState config =
    State <| StateRecord config Dict.empty Dict.empty Dict.empty


type alias SocketsDict =
    Dict.Dict String Connection


type alias QueuesDict =
    Dict.Dict String (List String)


type alias SubsDict msg =
    Dict.Dict String (List (String -> msg))


type Connection
    = Opening Int Process.Id
    | Connected WS.WebSocket



-- HANDLE APP MESSAGES


onEffects :
    Platform.Router msg Msg
    -> List (WebSocketCmd msg)
    -> List (MySub msg)
    -> State msg
    -> Task Never (State msg)
onEffects router cmds subs (State state) =
    let
        sendMessagesGetNewQueues =
            sendMessagesHelp cmds state.sockets state.queues

        newSubs =
            buildSubDict subs Dict.empty

        cleanup newQueues =
            let
                newEntries =
                    Dict.union newQueues (Dict.map (\k v -> []) newSubs)

                leftStep name _ getNewSockets =
                    getNewSockets
                        |> Task.andThen
                            (\newSockets ->
                                attemptOpen router 0 name
                                    |> Task.andThen (\pid -> Task.succeed (Dict.insert name (Opening 0 pid) newSockets))
                            )

                bothStep name _ connection getNewSockets =
                    Task.map (Dict.insert name connection) getNewSockets

                rightStep name connection getNewSockets =
                    closeConnection connection
                        |> Task.andThen (\_ -> getNewSockets)

                collectNewSockets =
                    Dict.merge leftStep bothStep rightStep newEntries state.sockets (Task.succeed Dict.empty)
            in
            collectNewSockets
                |> Task.andThen
                    (\newSockets ->
                        Task.succeed <|
                            State
                                { state
                                    | sockets = newSockets
                                    , queues = newQueues
                                    , subs = newSubs
                                }
                    )
    in
    sendMessagesGetNewQueues
        |> Task.andThen cleanup


sendMessagesHelp : List (WebSocketCmd msg) -> SocketsDict -> QueuesDict -> Task x QueuesDict
sendMessagesHelp cmds socketsDict queuesDict =
    case cmds of
        [] ->
            Task.succeed queuesDict

        (Send name msg) :: rest ->
            case Dict.get name socketsDict of
                Just (Connected socket) ->
                    WS.send socket msg
                        |> Task.andThen (\_ -> sendMessagesHelp rest socketsDict queuesDict)

                _ ->
                    sendMessagesHelp rest socketsDict (Dict.update name (add msg) queuesDict)


buildSubDict : List (MySub msg) -> SubsDict msg -> SubsDict msg
buildSubDict subs dict =
    case subs of
        [] ->
            dict

        (Listen name tagger) :: rest ->
            buildSubDict rest (Dict.update name (add tagger) dict)

        (KeepAlive name) :: rest ->
            buildSubDict rest (Dict.update name (Just << Maybe.withDefault []) dict)


add : a -> Maybe (List a) -> Maybe (List a)
add value maybeList =
    case maybeList of
        Nothing ->
            Just [ value ]

        Just list ->
            Just (value :: list)



-- HANDLE SELF MESSAGES


type Msg
    = Receive String String
    | Die String
    | GoodOpen String WS.WebSocket
    | BadOpen String


onSelfMsg : Platform.Router msg Msg -> Msg -> State msg -> Task Never (State msg)
onSelfMsg router selfMsg ((State s) as state) =
    case selfMsg of
        Receive name str ->
            let
                sends =
                    Dict.get name s.subs
                        |> Maybe.withDefault []
                        |> List.map (\tagger -> Platform.sendToApp router (tagger str))
            in
            Task.sequence sends
                |> Task.andThen (\_ -> Task.succeed state)

        Die name ->
            case Dict.get name s.sockets of
                Nothing ->
                    Task.succeed state

                Just _ ->
                    attemptOpen router 0 name
                        |> Task.andThen (\pid -> Task.succeed (updateSocket name (Opening 0 pid) state))

        GoodOpen name socket ->
            case Dict.get name s.queues of
                Nothing ->
                    Task.succeed (updateSocket name (Connected socket) state)

                Just messages ->
                    List.foldl
                        (\msg task -> WS.send socket msg |> Task.andThen (\_ -> task))
                        (Task.succeed (removeQueue name (updateSocket name (Connected socket) state)))
                        messages

        BadOpen name ->
            case Dict.get name s.sockets of
                Nothing ->
                    Task.succeed state

                Just (Opening n _) ->
                    attemptOpen router (n + 1) name
                        |> Task.andThen (\pid -> Task.succeed (updateSocket name (Opening (n + 1) pid) state))

                Just (Connected _) ->
                    Task.succeed state


updateSocket : String -> Connection -> State msg -> State msg
updateSocket name connection (State state) =
    State { state | sockets = Dict.insert name connection state.sockets }


removeQueue : String -> State msg -> State msg
removeQueue name (State state) =
    State { state | queues = Dict.remove name state.queues }



-- OPENING WEBSOCKETS WITH EXPONENTIAL BACKOFF


attemptOpen : Platform.Router msg Msg -> Int -> String -> Task x Process.Id
attemptOpen router backoff name =
    let
        goodOpen ws =
            Platform.sendToSelf router (GoodOpen name ws)

        badOpen _ =
            Platform.sendToSelf router (BadOpen name)

        actuallyAttemptOpen =
            open name router
                |> Task.andThen goodOpen
                |> Task.onError badOpen
    in
    Process.spawn (after backoff |> Task.andThen (\_ -> actuallyAttemptOpen))


open : String -> Platform.Router msg Msg -> Task WS.BadOpen WS.WebSocket
open name router =
    WS.open name
        { onMessage = \_ msg -> Platform.sendToSelf router (Receive name msg)
        , onClose = \details -> Platform.sendToSelf router (Die name)
        }


after : Int -> Task x ()
after backoff =
    if backoff < 1 then
        Task.succeed ()

    else
        Process.sleep (toFloat (10 * 2 ^ backoff))



-- CLOSE CONNECTIONS


closeConnection : Connection -> Task x ()
closeConnection connection =
    case connection of
        Opening _ pid ->
            Process.kill pid

        Connected socket ->
            WS.close socket
