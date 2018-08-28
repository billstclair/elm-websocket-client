# WebSockets for Elm 0.19

[billstclair/elm-websocket-client](https://package.elm-lang.org/packages/billstclair/elm-websocket-client/latest) is a conversion of the Elm 0.18 WebSocket client to Elm 0.19, using ports instead of native code and an effects module.

Elm 0.19 shipped with no WebSocket client. It used to be in [elm-lang/websocket](https://package.elm-lang.org/packages/elm-lang/websocket/latest). I have heard that its interface is being redesigned, and it will reappear sometime in the future. This package provides an alternative to use until then.

The package as shipped has a WebSocket simluator, which transforms messages you send with a function you provide and sends the result back. See the [example](https://github.com/billstclair/elm-websocket-client/tree/master/example) directory for instructions on setting up ports to make it use JavaScript code to do real WebSocket communication.
