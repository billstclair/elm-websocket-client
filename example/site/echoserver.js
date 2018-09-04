// echoserver.js
//
// A simple Node.js WebSocket echo server.
// Echoes everything you send it.
//
// If you send it a positive integer, it will shut down for
// that many seconds, and then restart.
//
// Start it with:
//
//   node echoserver.js [port]
//
// Where `port` is an optional port to listen on, default 8888.
//
// Required for this to work:
//
//    npm install -g ws
//

var port = 8888;
if (process.argv[2]) {
  port = process.argv[2];
}

var WSServer = require('ws').Server;
var wss;
function startListening() {
  wss = new WSServer({port: port});
  wss.on('connection', listen);
  console.log ("ws://localhost:" + port);
}

startListening();

function listen(ws) {
  console.log("connection");
  ws.send('connected');
  ws.on('message', function(message) {
    if (!isPositiveIntegerString(message)) {
      console.log('sending: "' + message + '"');
      ws.send(message);
    } else {
      var timeout = message;
      message = "Pausing for " + message + " seconds.";
      console.log(message);
      ws.send(message);
      wss.close();
      setTimeout(startListening, 1000 * timeout);
    }
  });
}
  
function isPositiveIntegerString(str) {
  var n = Math.floor(Number(str));
  if (isNaN(n)) return false;
  return ((String(n) === str) && (n > 0));
}

