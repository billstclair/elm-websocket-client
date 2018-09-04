# Changelog for billstclair/elm-websocket-client

## 2.0.1, 9/4/2018

* Fix some doc strings.

## 2.0.0, 9/4/2018

* Reconnect with exponential backoff after unexpected connection loss.
* Add a simple Node.js WebSocket echo server for testing.
* Queue sends while connection is being established or reconnection is in process.
* Reorganize socket state representation.
* Incompatible API changes:
  1. Added `PortVersion` type with a single value: `PortVersion2`
     I'll bump this when I make incompatible changes to the port JavaScript code, to remind you to update your site with the new `WebSocketClient.js`.
  2. Added `PortVersion` arg to `open`, `openWithKey`, and `send`.
  3. Added missing "o" to `UnsupprtedDataClosure`
  4. Added TimeOutOnReconnect to `ClosedCode`

## 1.0.1, 9/2/2018

* Fix default port names in non-standard port example in example/README.md
* Fix link to live page in top-level README.md

## 1.0.0, 9/2/2018

First published.
