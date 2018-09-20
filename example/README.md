# WebSocket Client Example

This directory provides an example of using `billstclair/elm-websocket-client` with or without ports.

To run the example without ports:

```bash
git clone git@github.com:billstclair/elm-websocket-client.git
cd elm-websocket-client/example
elm reactor
```

Then aim your browser at http://localhost:8000/src/Main.elm

The `Connect` button will send a command out through an unconnected port, so nothing will happen. Click `Close` to undo.

The `Simulated` button will do a simulated connect, after which `Send` and `Close` will function normally.

To run the example with ports:

```bash
git clone git@github.com:billstclair/elm-websocket-client.git
cd elm-websocket-client/example
bin/build
```

Then aim your browser at file:///.../elm-websocket-client/example/site/index.html

Where "..." is a path to the package directory, e.g. on my Mac it is: file:///Users/billstclair/elm/elm-websocket-client/example/site/index.html.

Or, if you have a browser that doesn't support `file://` URLs:

```bash
cd .../elm-websocket-client/example
elm reactor
```

And aim your web browser at http://localhost:8000/site/index.html

To hook up the ports to your own application, you need to define the two standard [billstclair/elm-port-funnel](https://package.elm-lang.org/packages/billstclair/elm-port-funnel/latest) ports in an included `port module` (as in `src/Main.elm`):

```elm
port cmdPort : Json.Encode.Value -> Cmd msg

port subPort : (Json.Encode.Value -> msg) -> Sub msg
```

Then copy the `example/site/js` directory into your site directory:

```bash
cd .../my-site
mkdir js
cp .../elm-websocket-client/example/site/js/* js/
```

Compile your top-level application file into your site directory:

```bash
cd .../my-project
elm make src/Main.elm --output .../my-site/elm.js
```

Then you need to set up your `index.html` much as I did in the `site` directory, customizing it for your applciation's needs.


## More Scripts

Install the NPM `ws` package, if it isn't already installed, and start the WebSocket echo server in `site/echoserver.js` on the port given as the optional parameter (default: 8888). If you send this server a positive integer, it will shut down for that many seconds. Useful for testing the code that automatically reconnects after a dropped connection:

```bash
bin/echoserver [port]
```

Compile src/Main.elm to `site/elm.js`, sync the `site` directory with the directory on my Mac where I store the `billstclair.github.io` repository, commit, and push. Not useful for anybody but me:

```bash
bin/update
```

Compile `src/simple.elm` to `site/index.js`. This is a very simple client that allows you to send JSON over the wire to the JavaScript port code. Mostly useful for initial debugging of that code:

```bash
bin/buildsimple
```
