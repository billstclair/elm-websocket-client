# Communication Protocols

WebSocketClient uses two protocols. One to talk between Elm and the port code, and one to talk between the package and the user code. In the old, native and effects manager implementation, the former was completely invisible to the user. Now the user code is an in-between, passing the `Value` that comes from the input port on to the library for interpretation, and returning each `Cmd` that is created by the library to the run-time from the user `update` function.

## Between User Code and the WebSocketClient Package

I'm leaving out the function bodies here.

### Sending Commands out the Output Port

The output port is in a `Config` instance inside the `State`.

    -- The url itself will be used as key
    open : String -> State msg -> (State msg, Cmd msg)
    open url state = ...

    openWithKey : String -> String -> State msg -> (State msg, Cmd msg)
    openWithKey key url state = ...

    close : String -> State msg -> (State msg, Cmd msg)
    close key state = ...

    bytesQueued : String -> State msg -> (State msg, Cmd msg)
    bytesQueued key state = ...

    type Message
      = Connected { key : String, description : String }
      | MessageReceived { key : String, message : String }
      | Closed { key : String, code : String, reason : String, wasClean : Bool }
      | BytesQueued { key : String, bufferedAmount : Int }
      | Error { key : Maybe String, code : String, description : String }

### Receiving Commands from the Output Port

    -- Call this on receiving a value through the subscription port
    -- Update the stored `State` from the received updated state.
    update : Value -> State msg -> (State msg, Message)

## Between Elm and the Port Code

There are two ports, `inPort`, which is subscribed to get messages from port code to Elm, and `outPort`, which is used to send commands from Elm to the port code. From the Elm side, everything is JSON encoded as a `Value`, so it's available just as documented below to JavaScript. I'll write simple JSON encoders and decoders for these, but users will never care about them. They'll just pass the `Value` to `WebSocketClient.update`.

The general form of the port messages is:

    { function: <string>
    , args : { name: <value>, ... }
    }
    
### Commands Sent TO the Port Code

Open a socket. Each socket has a unique key. Initially, this will just be the URL, but having the user allocate unique names allows multiple sockets to be open to the same URL.

    { function: "open"
    , args : { key : <string>
             , url : <string>
             }
    }

Send a message out through a socket.

    { function: "send"
    , args : { key : <string>
             , message : <string>
             }
    }

Close a socket.

    { function: "close"
    , args : { key : <string>
             , reason : <string>
             }
    }

Request bytes queued:

    { function: "bytesQueued"
    , args : { key : <string>
             }
    }

### Responses FROM the Port Code

If opening a socket succeeds:

    { function: "connected"
    , args : { key : <string>
             , description : <string>
             }
    }

On receiving a message:

    { function: "messageReceived"
    , args : { key : <string>
             , message : <string>
             }
             
Reporting on results of a close:

    { function: "closed"
    , args : { key : <string>
             , code : <string>
             , reason : <string>
             , wasClean : <boolean>
             }
    }

Reporting bytes queued:

    { function: "bytesQueued"
    , args : { key : <string>
             , bufferedAmount : <integer>
             }
    }

If an errror happens:

    { function: "error"
    , args : { key : <string>      # null if no socket associated
             , code : <string>
             , description : <string>
             }
    }
