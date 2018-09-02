# WebSockets for Elm 0.19

[billstclair/elm-websocket-client](https://package.elm-lang.org/packages/billstclair/elm-websocket-client/latest) is a conversion of the Elm 0.18 WebSocket client to Elm 0.19, using ports instead of native code and an effects module.

The package works, but it does not yet automatically reconnect if the connection goes down unexpectedly. The API won't change when I add that, so you can start to program against it now, and the connections will get more reliable in a future release.

Elm 0.19 shipped with no WebSocket client. It used to be in [elm-lang/websocket](https://package.elm-lang.org/packages/elm-lang/websocket/latest). I have heard that its interface is being redesigned, and it will reappear sometime in the future. This package provides an alternative to use until then.

The package as shipped will work with a WebSocket simulator, which transforms messages you send with a function you provide and sends the result back immediately. See the [example](https://github.com/billstclair/elm-websocket-client/tree/master/example) README for instructions on setting up ports to make it use JavaScript code to do real WebSocket communication.

The example is live at [billstclair.github.io/elm-websocket-client](https://billstclair.github.io/websocket-client/).
