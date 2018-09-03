// echoserver.js
//
// A simple Node.js WebSocket echo server.
//
// Start it with:
//
//   node echoserver.js [port]
//
// Where port is an optional port to listen on, default 8888.
//

var port = 8888;
if (process.argv[2]) {
  port = process.argv[2];
}

var WSServer = require('ws').Server
var wss      = new WSServer({host: "localhost", port: 8888})

console.log ("Listening on ws://localhost:" + port);
  
// handle only pure clean websockets
wss.on('connection', function(ws) {
  ws.on('message', function(message) {
    ws.send(message);
  })
})
