# WebSocket Client Example

This directory provides an example of using `billstclair/elm-websocket-client` with or without ports.

To run the example without ports:

    git clone git@github.com:billstclair/elm-websocket-client.git
    cd elm-websocket-client/example
    elm reactor

Then aim your browser at http://localhost:8000/src/Main.elm

The `Connect` button will send a command out through an unconnected port, so nothing will happen. Click `Close` to undo.

The `Simulated` button will do a simulated connect, after which `Send` and `Close` will function normally.

To run the example with ports:

    git clone git@github.com:billstclair/elm-websocket-client.git
    cd elm-websocket-client/example
    bin/build

Then aim your browser at file:///.../elm-websocket-client/example/site/index.html

Where "..." is a path to the package directory, e.g. on my Mac it is: file:///Users/billstclair/elm/elm-websocket-client/example/site/index.html.

To hook up the ports to your own application, you need to define the two ports in your toplevel file:

    port webSocketClientCmd : Json.Encode.Value -> Cmd msg

    port webSocketClientSub : (Json.Encode.Value -> msg) -> Sub msg

Then copy the `example/site/js` directory into your site directory:

    cd .../my-site
    mkdir js
    cp .../elm-websocket-client/example/site/js/* js/
    
Compile your top-level application file into your site directory:

    cd .../my-project
    elm make src/Main.elm --output .../my-site/index.js

Then you need to set up your `index.html` much as I did in the `site` directory (adding any other port code you need):

    <html>
      <head>
        ...
        <script type='text/javascript' src='index.js'></script>
        <script type='text/javascript' src='js/WebSocketClient.js'></script>
      </head>
      <body>
        <div id='elm'></div>
        <script type='text/javascript'>

    // initialize your flags here, if you have them.
    var flags = undefined;
    
    // Initialize the name of your main module here
    var mainModule = 'Main';

    // Change "PortExample" to your application's module name.
    var app = Elm[mainModule].init({
      node: document.getElementById('elm'),
      flags: flags
    });

    // If you use non-standard names for the ports, you need to name them:
    //
    //   WebSocketClient.subscribe(app, 'webSocketClientToJs', 'jsToWebSocketClient');
    //
    WebSocketClient.subscribe(app);
        </script>
      </body>
    </html>
