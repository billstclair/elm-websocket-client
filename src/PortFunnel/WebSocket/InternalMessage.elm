---------------------------------------------------------------------
--
-- InternalMessage.elm
-- The internals of the PortFunnel.WebSocket.Message type.
-- Copyright (c) 2018 Bill St. Clair <billstclair@gmail.com>
-- Some rights reserved.
-- Distributed under the MIT License
-- See LICENSE
--
----------------------------------------------------------------------


module PortFunnel.WebSocket.InternalMessage exposing
    ( InternalMessage(..)
    , PIClosedRecord
    , PIErrorRecord
    )

import Dict exposing (Dict)
import Json.Decode as JD exposing (Decoder)
import Json.Encode as JE exposing (Value)


type alias PIClosedRecord =
    { key : String
    , bytesQueued : Int
    , code : Int
    , reason : String
    , wasClean : Bool
    }


type alias PIErrorRecord =
    { key : Maybe String
    , code : String
    , description : String
    , name : Maybe String
    , message : Maybe String
    }


type InternalMessage
    = Startup
      -- output
    | POOpen { key : String, url : String }
    | POSend { key : String, message : String }
    | POClose { key : String, reason : String }
    | POBytesQueued { key : String }
    | PODelay { millis : Int, id : String }
      -- loop
    | PLoopOpen { key : String, url : String }
    | PLoopSend { key : String, message : String }
    | PLoopClose { key : String, reason : String }
      -- input
    | PIConnected { key : String, description : String }
    | PIMessageReceived { key : String, message : String }
    | PIClosed PIClosedRecord
    | PIBytesQueued { key : String, bufferedAmount : Int }
    | PIDelayed { id : String }
    | PIError PIErrorRecord
