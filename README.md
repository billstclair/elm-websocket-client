# WebSockets for Elm 0.19

[billstclair/elm-websocket-client](https://package.elm-lang.org/packages/billstclair/elm-websocket-client/latest) is a conversion of the Elm 0.18 WebSocket client to Elm 0.19, using ports instead of native code and an effects module.

Elm 0.19 shipped with no WebSocket client. It used to be in [elm-lang/websocket](https://package.elm-lang.org/packages/elm-lang/websocket/latest). I have heard that its interface is being redesigned, and it will reappear sometime in the future. This package provides an alternative to use until then.

The package as shipped will work with a pure Elm WebSocket simulator, which transforms messages you send with a function you provide and sends the result back immediately. See the [example](https://github.com/billstclair/elm-websocket-client/tree/master/example) README for instructions on setting up ports to make it use JavaScript code to do real WebSocket communication.

The example is live at [billstclair.github.io/elm-websocket-client](https://billstclair.github.io/elm-websocket-client/).

## Keys and URLs

The old `WebSocket` package identified sockets by their URLs. You can do that with `WebSocketClient` if you want, by using the `open` function. But you can also assign a unique key to each connection, which enables multiple connections to a single URL, by using `openWithKey`. The `key` arg to the other action functions will be the URL if you used `open` or the `key` if you used `openWithKey`.

## Using the Package

The Elm 0.18 `WebSocket` module, in the `elm-lang/websocket` package, was an `effect module`. This allowed it to update its state in the background, so your code didn't have to have anything to do with that. A regular `port module` isn't that lucky. The state for the `WebSocketClient` module in the `billstclair/elm-websocket-client` package needs to be stored in your application's `Model`, and you have to update it when you call its functions, or process a `Value` you receive from its subscription port.

The code below is similar to `example/src/Main.elm`.

First you need declare your top-level module to support ports and you need to define the ports:

    port module Main exposing (main)
    
    import Json.Encode exposing (Value)
    import WebSocketClient exposing
         ( Config, State, Response(..), PortVersion(..)
         , makeConfig, makeState
         )

    port webSocketClientCmd : Value -> Cmd msg
    port webSocketClientSub : (Value -> msg) -> Sub msg

Your Model needs a place to store the `WebSocketClient` state:

    type alias Model =
        { ...
        , state : WebSocketClient.State Msg
          ...
        }

You need a `Msg` to wrap the subscription port, and you need to subscribe to it:

    type Msg
         = ...
         | Receive Value
       
    subscriptions: Model -> Sub Msg
    subscriptions model =
        webSocketClientSub Receive

You need to initialize that state:

    -- A real config that uses your output port
    config : Config Msg
    config =
        WebSocketClient.makeConfig webSocketClientCmd

    -- A simulated config that echoes your output.
    -- Will work in `elm reactor`.
    simulatorConfig : Config Msg
    simulatorConfig =
        WebSocketClient.makeSimulatorConfig (\string -> Just string)
      
    -- In the shipped example, this choice is provided by two buttons.
    useSimulator : Bool
    useSimulator =
        False

    init : () -> (Model, Cmd Msg)
    init _ =
        ( { ...
          , state = WebSocketClient.makeState
                      (if useSimulator then
                         simulatorConfig
                       else
                         config
                      )
            ...
          }
        , Cmd.none
        )

You need to handle the `Receive` message in your `update` function:

    update : Msg -> Model -> (Model, Cmd Msg)
    update msg model =
        case msg of
          ...

          Receive value ->
            WebSocketClient.process model.state value
              |> processResponse model

          ...

You need to `open` a port before you call `send` on it, and `close` it when you're done with it, processing the returns, which, except for errors, will be commands to send out of your port.

Note the `PortVersion2` arg to `open` and `send`. If a new version of the package changes the JavaScript port code incompatibly, the single value of type `PortVersion` will change, so that your code will fail to compile until you change it. This will hopefully remind you to update the `WebSocketClient.js` file with the new version.

    WebSocketClient.open PortVersion2 model.state <url>
        |> processResponse model

    WebSocketClient.send PortVersion2 model.state <url> <message>
        |> processResponse model

    WebSocketClient.close model.state <url>
        |> processResponse model

Finally, you have to process the `Response` data that comes back from the `WebSocketClient` action functions:

    processResponse : Model -> ( State Msg, Response Msg ) -> ( Model, Cmd Msg )
    processResponse model ( state, response ) =
        let
            mdl =
                { model | state = state }
        in
        case response of
            -- Nothing to see here. Move along.
            NoResponse ->
                ( model, Cmd.none )

            -- This is how commands get sent out the `webSocketClientCmd` port
            CmdResponse cmd ->
                ( model, cmd )

            -- And this is how you receive a message from the server.
            -- If you have multiple sockets open, you'll have to use
            -- the `key` field to determine which one it came from.
            MessageReceivedResponse { key, message } ->
              ...

            -- You may ignore the responses below here, unless you want
            -- to track progress and errors.

            -- Sent when the connection has been made.
            -- `key` is the `url` for `open` or the `key` for `openWithKey`.
            -- `description` is a human-readable description.
            -- If you `send` message before receiving this, they will be queued
            -- and actually sent after the connection has been made.
            ConnectedResponse { key, description } ->
              ...

            -- You may need to clean up here, especially if `expected` is False.
            -- I'll add restablishment of dropped connections soon, but
            -- it's not there yet.
            ClosedResponse { key, code, wasClean, expected } ->
              ...

            -- `WebSocketClient.errorToString` can be useful here.
            -- You probably won't see any of these.
            ErrorResponse error ->
              ...
