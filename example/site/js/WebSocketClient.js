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

function subscribe(app, webSocketClientToJsName, jsToWebSocketClientName) {
  if (!webSocketClientToJsName) {
    webSocketClientToJsName = 'webSocketClientToJs';
  }
  if (!jsToWebSocketClientName) {
    jsToWebSocketClientName = 'jsToWebSocketClient';
  }

  ports = app.ports;
  var jsToWebSocketClientPort = ports[jsToWebSocketClientName];
  var webSocketClientToJsPort = ports[webSocketClientToJsName];

  webSocketClientToJsPort.subscribe(function(command) {
    var returnValue = commandDispatch(command);
    jsToWebSocketClientPort.send(returnValue);
  });  
}

function errorReturn(args) {
  return { tag: "error",
           args : args
         }
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
      return errorReturn({ code: "badargs",
                           description: "Args were not an object: " +
                             JSON.stringify(args)
                         });
    }
    return errorReturn({ code: "badfunc",
                         description: "Bad func: " + JSON.stringify(tag)
                       });
  }
  return errorReturn({ code: "badcommand",
                       description: "Bad command " + JSON.stringify(command)
                     });
}

var functions = {
  open: doOpen,
  send: doSend,
  close: doClose,
  bytesQueued: doBytesQueued
};

function unimplemented(func, args) {
  return errorReturn ({ code: "unimplemented",
                        description: "Not implemented: "+ func + "(" +
                           JSON.stringify(args) +
                           ")"
                      });
}

function doOpen(args) {
  return unimplemented("doOpen", args);
} 

function doSend(args) {
  return unimplemented("doSend", args);
} 

function doClose(args) {
  return unimplemented("doClose", args);
} 

function doBytesQueued(args) {
  return unimplemented("doBytesQueued", args);
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
