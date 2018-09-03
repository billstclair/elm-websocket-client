# Communication Protocols

WebSocketClient uses two protocols. One to talk between Elm and the port code, and one to talk between the package and the user code. In the old, native and effects manager implementation, the former was completely invisible to the user. Now the user code is an in-between, passing the `Value` that comes from the input port on to the library for interpretation, and returning each `Cmd` that is created by the library to the run-time from the user `update` function.

I did most of this before watching Murphy Randall's [ports talk](https://www.youtube.com/watch?v=P3pL85n9_5s), but I'm calling my function name parameter "tag" because of that.

## Between User Code and the WebSocketClient Package

I'm leaving out the function bodies here.

### Sending Commands through the Output Port

The output port is in a `Config` instance inside the `State`.

    -- The url itself will be used as key
    open : String -> State msg -> (State msg, Cmd msg)
    open url state = ...

    openWithKey : String -> String -> State msg -> (State msg, Cmd msg)
    openWithKey key url state = ...

    send : String -> String -> State msg -> (State msg, Cmd msg)
    send key message state = ...

    close : String -> State msg -> (State msg, Cmd msg)
    close key state = ...

    bytesQueued : String -> State msg -> (State msg, Cmd msg)
    bytesQueued key state = ...

    sleep : String -> Int -> State msg -> (State msg, Cmd msg)
    sleep key backoff = ...

### Processing Values Received from the Input Port Subscription

    type Message
      = Connected { key : String, description : String }
      | MessageReceived { key : String, message : String }
      | Closed { key : String, code : String, reason : String, wasClean : Bool }
      | BytesQueued { key : String, bufferedAmount : Int }
      | Slept { key : String, backoff }
      | Error { key : Maybe String
              , code : String
              , description : String
              , name : Maybe String
              }

    -- Call this on receiving a value through the subscription port
    -- Update the stored `State` from the received updated state.
    update : Value -> State msg -> (State msg, Message)

## Between Elm and the Port Code

There are two ports, `inPort`, which is subscribed to get messages from port code to Elm, and `outPort`, which is used to send commands from Elm to the port code. From the Elm side, everything is JSON encoded as a `Value`, so it's available just as documented below to JavaScript. I'll write simple JSON encoders and decoders for these, but users will never care about them. They'll just pass the `Value` to `WebSocketClient.update`.

The general form of the port messages is:

    { tag: <string>
    , args : { name: <value>, ... }
    }
    
### Commands Sent TO the Port Code

Open a socket. Each socket has a unique key. Initially, this will just be the URL, but having the user allocate unique names allows multiple sockets to be open to the same URL.

    { tag: "open"
    , args : { key : <string>
             , url : <string>
             }
    }

Send a message out through a socket.

    { tag: "send"
    , args : { key : <string>
             , message : <string>
             }
    }

Close a socket.

    { tag: "close"
    , args : { key : <string>
             , reason : <string>
             }
    }

Request bytes queued:

    { tag: "bytesQueued"
    , args : { key : <string>
             }
    }

Request sleep for 10 x 2^backoff milliseconds (`setTimeout` in JS):

    { tag: "sleep"
    , args : { key : <string>
             , backoff : <string>
             }
    }

### Responses FROM the Port Code

If opening a socket succeeds:

    { tag: "connected"
    , args : { key : <string>
             , description : <string>
             }
    }

On receiving a message:

    { tag: "messageReceived"
    , args : { key : <string>
             , message : <string>
             }
             
Reporting on results of a close:

    { tag: "closed"
    , args : { key : <string>
             , code : <string>
             , reason : <string>
             , wasClean : <boolean string ("true" or anything else for false)>
             }
    }

Reporting bytes queued:

    { tag: "bytesQueued"
    , args : { key : <string>
             , bufferedAmount : <integer string>
             }
    }

Sleep done:

    { tag: "slept"
    , args : { key : <string>
             , backoff : <string>
             }
    }


If an errror happens:

    { tag: "error"
    , args : { key : <string>      # optional
             , code : <string>
             , description : <string>
             , name : <string>     # err.name, may be null
             }
    }
