//////////////////////////////////////////////////////////////////////
//
// WebSocketClient.js
// JavaScript runtime code for Elm WebSocketClient
// Copyright (c) 2018 Bill St. Clair <billstclair@gmail.com>
// Portions Copyright (c) 2016 
// Some rights reserved.
// Distributed under the MIT License
// See LICENSE.txt
//
//////////////////////////////////////////////////////////////////////


// The single global variable defined by this file.
// It is an object with a single `subscribe` property, a function:
//
//   WebSocketClientJS.subscribe(app,
//                               [webSocketClientToJsPortName,
//                                [jsToWebSocketClientPortName]]);
//
// webSocketClientToJsPortName defaults to 'webSocketClientToJsPort'.
// jsToWebSocketClientPortName defaults to 'jsToWebSocketClientPort'.
//
var WebSocketClient = {};

(function() {

WebSocketClient.subscribe = subscribe;

function subscribe(app, webSocketClientToJsPortName, jsToWebSocketClientPortName) {
  if (!webSocketClientToJsPortName) {
    webSocketClientToJsPortName = 'webSocketClientToJs';
  }
  if (!jsToWebSocketClientPortName) {
    jsToWebSocketClientPortName = 'jsToWebSocketClient';
  }

  var ports = app ? app.ports : null;
  if (!ports) {
    console.log('There is no "ports" property on:', app);
    return;
  }

  var jsToWebSocketClientPort = ports[jsToWebSocketClientPortName];
  if (!jsToWebSocketClientPort) {
    console.log('There is no port named: ' + jsToWebSocketClientPortName);
    return;
  }

  var webSocketClientToJsPort = ports[webSocketClientToJsPortName];
  if (!webSocketClientToJsPort) {
    console.log('There is no port named: ' + webSocketClientToJsPortName);
    return;
  }

  webSocketClientToJsPort.subscribe(function(command) {
    var returnValue = commandDispatch(command);
    jsToWebSocketClientPort.send(returnValue);
  });  
}

function commandDispatch(command) {
  // For testing
  return command;
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
