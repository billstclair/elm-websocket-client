# WebSockets for Elm 0.19

[billstclair/elm-websocket-client](https://package.elm-lang.org/packages/billstclair/elm-websocket-client/latest) is a conversion of the Elm 0.18 WebSocket client to Elm 0.19, using ports instead of native code and an effects module.

Elm 0.19 shipped with no WebSocket client. It used to be in [elm-lang/websocket](https://package.elm-lang.org/packages/elm-lang/websocket/latest). I have heard that its interface is being redesigned, and it will reappear sometime in the future. This package provides an alternative to use until then.

The package as shipped will work with a pure Elm WebSocket simulator, which transforms messages you send with a function you provide and sends the result back immediately. See the [example](https://github.com/billstclair/elm-websocket-client/tree/master/example) README for instructions on setting up ports to make it use JavaScript code to do real WebSocket communication.

The example is live at [billstclair.github.io/elm-websocket-client](https://billstclair.github.io/elm-websocket-client/).

## Keys and URLs

The old `WebSocket` package identified sockets by their URLs. You can do that with `WebSocketClient` if you want, by using the `open` function. But you can also assign a unique key to each connection, which enables multiple connections to a single URL, by using `openWithKey`. The `key` arg to the other action functions will be the URL if you used `open` or the `key` if you used `openWithKey`.

## Using the Package

The Elm 0.18 `WebSocket` module, in the `elm-lang/websocket` package, was an `effect module`. This allowed it to update its state in the background, so your code didn't have to have anything to do with that. A regular `port module` isn't that lucky. The state for the `WebSocketClient` module needs to be stored in your application's `Model`, and you have to update it when you call its functions, or process a `Value` you receive from its subscription port.

See `Main.elm` and `PortFunnels.elm` in the the [example/src](https://github.com/billstclair/elm-websocket-client/tree/master/example/src) directory for details. `PortFunnels.elm` exposes a `State` type and an `initialState` constant.

You will usually copy `PortFunnels.elm` into your application's source directory, and, if you use other `PortFunnel` modules, modify it to support all of them. It is a `port module`, and it defines the two ports that are used by `example/site/index.html`, `cmdPort` and `subPort`.
