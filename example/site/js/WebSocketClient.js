//////////////////////////////////////////////////////////////////////
//
// WebSocketClient.js
// JavaScript runtime code for Elm WebSocketClient
// Copyright (c) 2018 Bill St. Clair <billstclair@gmail.com>
// Portions Copyright (c) 2016 Evan Czaplicki
// Some rights reserved.
// Distributed under the MIT License
// See LICENSE
//
//////////////////////////////////////////////////////////////////////

// WebSocketClient is the single global variable defined by this file.
// It is an object with a `subscribe` property, a function, called as:
//
//   WebSocketClientJS.subscribe(app,
//                               [webSocketClientToJsName],
//                               [jsToWebSocketClientName]);
//
// webSocketClientToJsName defaults to 'webSocketClientToJs'.
// jsToWebSocketClientName defaults to 'jsToWebSocketClient'.
// They name Elm ports.

var WebSocketClient = {};

(function() {

WebSocketClient.subscribe = subscribe;

var returnPort;

function subscribe(app, webSocketClientToJsName, jsToWebSocketClientName) {
  if (!webSocketClientToJsName) {
    webSocketClientToJsName = 'webSocketClientToJs';
  }
  if (!jsToWebSocketClientName) {
    jsToWebSocketClientName = 'jsToWebSocketClient';
  }

  ports = app.ports;
  returnPort = ports[jsToWebSocketClientName];
  var cmdPort = ports[webSocketClientToJsName];

  cmdPort.subscribe(function(command) {
    var returnValue = commandDispatch(command);
    if (returnValue) returnPort.send(returnValue);
  });  
}

function objectReturn(tag, args) {
  return { tag: tag, args : args };
}

function keyedErrorReturn(key, code, description) {
  return objectReturn("error", { key: key, code: code, description: description });
}
function errorReturn(code, description) {
  return objectReturn("error", { code: code, description: description });
}

function commandDispatch(command) {
  if (typeof(command) == 'object') {
    var tag = command.tag;
    var f = functions[tag];
    if (f) {
      var args = command.args;
      if (typeof(args) == 'object') {
        return f(args);
      }
      return errorReturn("badargs",
                         "Args not an object: " + JSON.stringify(args));
    }
    return errorReturn("badtag",
                       "Bad tag: " + JSON.stringify(tag));
  }
  return errorReturn("badcommand",
                     "Bad command " + JSON.stringify(command));
}

var functions = {
  open: doOpen,
  send: doSend,
  close: doClose,
  bytesQueued: doBytesQueued
};

function unimplemented(func, args) {
  return errorReturn ("unimplemented",
                      "Not implemented: "+ func +
                      "(" + JSON.stringify(args) + ")");
}

var sockets = {}

function doOpen(args) {
  var key = args.key;
  var url = args.url;
  if (!key) key = url;
  if (sockets[key]) {
    return errorReturn("keyused", "Key already has a socket open: " + key);
  }
  try {
	var socket = new WebSocket(url);
    sockets[key] = socket;
  }
  catch(err) {
    // May need to encode err.name in the error.
    // The old code returned BadSecurity if it was 'SecurityError'
    // or BadArgs otherwise.
    return errorReturn('openfailed', "Can't create socket for URL: " + url)
  }
  socket.addEventListener("open", function(event) {
    console.log("Socket connected for URL: " + url);
    returnPort.send(objectReturn("connected",
                                 { key: key,
                                   description: "Socket connected for URL: " + url
                                 }));
  });
  socket.addEventListener("message", function(event) {
    var message = event.data;
    console.log("Received for '" + key + "': " + message);
    returnPort.send(objectReturn("messageReceived",
                                 { key: key, message: message }));
  });
  socket.addEventListener("close", function(event) {
	console.log("'" + key + "' closed");
    returnPort.send(objectReturn("closed",
                                 { key: key,
                                   code: "" + event.code,
                                   reason: "" + event.reason,
                                   wasClean: event.wasClean ? "true" : "false"
                                 }));
  });
  return null;
} 

function socketNotOpenReturn(key) {
  return keyedErrorReturn(key, 'notopen', 'Socket not open');
}

function doSend(args) {
  var key = args.key;
  var message = args.message;
  var socket = sockets[key];
  if (!socket) {
    return socketNotOpenReturn(key);
  }
  try {
	socket.send(message);
  } catch(err) {
    return keyedErrorReturn(key, 'badsend', 'Send error')
  }
  return null;
} 

function doClose(args) {
  var key = args.key;
  var reason = args.reason;
  var socket = sockets[key];
  if (!socket) {
    return socketNotOpenReturn(key);
  }
  try {
    // Should this happen in the event listener?
    delete sockets[key];
    socket.close();
  } catch(err) {
    // May need to return err.name somehow.
    // The old code returned BadReason if it was 'SyntaxError'
    // or BadCode otherwise
    return keyedErrorReturn(key, 'badclose', 'Close error')
  }
} 

function doBytesQueued(args) {
  var key = args.key;
  var socket = sockets[key];
  if (!socket) {
    return socketNotOpenReturn(key);
  }
  returnPort.send(objectReturn("closed",
                               { key: key,
                                 bytesQueued: "" + socket.bufferedAmount
                               }));
} 

})();
