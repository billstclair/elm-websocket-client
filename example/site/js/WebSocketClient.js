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

/*
var _WebSocket_open = F2(function(url, settings)
{
	return __Scheduler_binding(function(callback)
	{
		try
		{
			var socket = new WebSocket(url);
		}
		catch(err)
		{
			return callback(__Scheduler_fail(
				err.name === 'SecurityError' ? __WS_BadSecurity : __WS_BadArgs
			));
		}

		socket.addEventListener("open", function(event) {
			callback(__Scheduler_succeed(socket));
		});

		socket.addEventListener("message", function(event) {
			__Scheduler_rawSpawn(A2(settings.onMessage, socket, event.data));
		});

		socket.addEventListener("close", function(event) {
			__Scheduler_rawSpawn(settings.onClose({
				__$code: event.code,
				__$reason: event.reason,
				__$wasClean: event.wasClean
			}));
		});

		return function()
		{
			if (socket && socket.close)
			{
				socket.close();
			}
		};
	});
});


var _WebSocket_send = F2(function(socket, string)
{
	return __Scheduler_binding(function(callback)
	{
		var result =
			socket.readyState === WebSocket.OPEN
				? __Maybe_Nothing
				: __Maybe_Just(__WS_NotOpen);

		try
		{
			socket.send(string);
		}
		catch(err)
		{
			result = __Maybe_Just(__WS_BadString);
		}

		callback(__Scheduler_succeed(result));
	});
});


var _WebSocket_close = F3(function(code, reason, socket)
{
	return __Scheduler_binding(function(callback) {
		try
		{
			socket.close(code, reason);
		}
		catch(err)
		{
			return callback(__Scheduler_fail(__Maybe_Just({
				err.name === 'SyntaxError' ? __WS_BadReason : __WS_BadCode
			})));
		}
		callback(__Scheduler_succeed(__Maybe_Nothing));
	});
});


function _WebSocket_bytesQueued(socket)
{
	return __Scheduler_binding(function(callback) {
		callback(__Scheduler_succeed(socket.bufferedAmount));
	});
}
*/
