# Changelog for billstclair/elm-websocket-client

## 4.0.0, 10/12/2018

Add `ReconnectedResponse` and return it when the connection is re-established after being lost.

Add `reconnectedResponses` (and `filterResponses` and `isReconnectedResponse`) to aid in filtering a `ListResponse`, which may contain a `ReconnectedResponse`.

## 3.0.2, 10/11/2018

* Make the JavaScript code work with WebPack (issue #3).

* Fix documentation issues, #1 & #2.

## 3.0.1, 10/1/2018

* Update example to use `PortFunnels.elm` for all the baroque dispatching.

## 3.0.0, 9/22/2018

* Join the [billstclair/elm-port-funnel](https://package.elm-lang.org/packages/billstclair/elm-port-funnel/latest) ecosystem.

* `setAutoReopen` and `willAutoReopen` to control automatic reconnection on unexpected connection loss.

## 2.0.2, 9/4/2018

* Remove README paragraph about no automatic reconnect. It was there in 2.0.0.

* Implement `keepAlive`. Can't imagine anyone using it, instead of just ignoring `MessageReceivedResponse`, but it was in the original `WebSocket` module, so I'm keeping it.

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
