-- This is just a place to stash the old Effects code
-- until I integrate this functionality into WebSocketClient.elm.
-- It won't build, and will go away once the package is fully functional.


module Main exposing (Msg(..), add, after, attemptOpen, buildSubDict, closeConnection, onEffects, onSelfMsg, open, removeQueue, sendMessagesHelp, updateSocket)


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
