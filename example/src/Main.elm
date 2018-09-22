port module Main exposing (main)

{-| WebSocketClient Example
-}

import Browser
import Cmd.Extra exposing (addCmd, addCmds, withCmd, withCmds, withNoCmd)
import Dict exposing (Dict)
import Html exposing (Html, a, button, div, h1, input, p, span, text)
import Html.Attributes exposing (checked, disabled, href, size, style, type_, value)
import Html.Events exposing (onClick, onInput)
import Json.Encode exposing (Value)
import PortFunnel exposing (FunnelSpec, GenericMessage, ModuleDesc, StateAccessors)
import PortFunnel.WebSocket as WebSocket


port cmdPort : Value -> Cmd msg


port subPort : (Value -> msg) -> Sub msg


subscriptions : Model -> Sub Msg
subscriptions model =
    subPort Process


simulatedCmdPort : Value -> Cmd Msg
simulatedCmdPort =
    WebSocket.makeSimulatedCmdPort Process


getCmdPort : Model -> (Value -> Cmd Msg)
getCmdPort model =
    if model.useSimulator then
        simulatedCmdPort

    else
        cmdPort


type alias FunnelState =
    { socket : WebSocket.State }



-- MODEL


defaultUrl : String
defaultUrl =
    "wss://echo.websocket.org"


type alias Model =
    { send : String
    , log : List String
    , url : String
    , useSimulator : Bool
    , wasLoaded : Bool
    , state : FunnelState
    , key : String
    , error : Maybe String
    }


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


initialFunnelState : FunnelState
initialFunnelState =
    { socket = WebSocket.initialState }


init : () -> ( Model, Cmd Msg )
init _ =
    { send = "Hello World!"
    , log = []
    , url = defaultUrl
    , useSimulator = True
    , wasLoaded = False
    , state = initialFunnelState
    , key = "socket"
    , error = Nothing
    }
        |> withNoCmd


socketAccessors : StateAccessors FunnelState WebSocket.State
socketAccessors =
    StateAccessors .socket (\substate state -> { state | socket = substate })


type alias AppFunnel substate message response =
    FunnelSpec FunnelState substate message response Model Msg


type Funnel
    = SocketFunnel (AppFunnel WebSocket.State WebSocket.Message WebSocket.Response)


funnels : Dict String Funnel
funnels =
    Dict.fromList
        [ ( WebSocket.moduleName
          , FunnelSpec socketAccessors
                WebSocket.moduleDesc
                WebSocket.commander
                socketHandler
                |> SocketFunnel
          )
        ]



-- UPDATE


type Msg
    = UpdateSend String
    | UpdateUrl String
    | ToggleUseSimulator
    | ToggleAutoReopen
    | Connect
    | Close
    | Send
    | Process Value


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateSend newsend ->
            { model | send = newsend } |> withNoCmd

        UpdateUrl url ->
            { model | url = url } |> withNoCmd

        ToggleUseSimulator ->
            { model | useSimulator = not model.useSimulator } |> withNoCmd

        ToggleAutoReopen ->
            let
                state =
                    model.state

                socketState =
                    state.socket

                autoReopen =
                    WebSocket.willAutoReopen model.key socketState
            in
            { model
                | state =
                    { state
                        | socket =
                            WebSocket.setAutoReopen
                                model.key
                                (not autoReopen)
                                socketState
                    }
            }
                |> withNoCmd

        Connect ->
            { model
                | log =
                    (if model.useSimulator then
                        "Connecting to simulator"

                     else
                        "Connecting to " ++ model.url
                    )
                        :: model.log
            }
                |> withCmd
                    (WebSocket.makeOpenWithKey model.key model.url
                        |> send model
                    )

        Send ->
            { model
                | log =
                    ("Sending \"" ++ model.send ++ "\"") :: model.log
            }
                |> withCmd
                    (WebSocket.makeSend model.key model.send
                        |> send model
                    )

        Close ->
            { model
                | log = "Closing" :: model.log
            }
                |> withCmd
                    (WebSocket.makeClose model.key
                        |> send model
                    )

        Process value ->
            case
                PortFunnel.processValue funnels
                    appTrampoline
                    value
                    model.state
                    model
            of
                Err error ->
                    { model | error = Just error } |> withNoCmd

                Ok res ->
                    res


appTrampoline : GenericMessage -> Funnel -> FunnelState -> Model -> Result String ( Model, Cmd Msg )
appTrampoline genericMessage funnel state model =
    let
        theCmdPort =
            getCmdPort model
    in
    case funnel of
        SocketFunnel appFunnel ->
            PortFunnel.appProcess theCmdPort
                genericMessage
                appFunnel
                state
                model


send : Model -> WebSocket.Message -> Cmd Msg
send model message =
    WebSocket.send (getCmdPort model) message


doIsLoaded : Model -> Model
doIsLoaded model =
    if not model.wasLoaded && WebSocket.isLoaded model.state.socket then
        { model
            | useSimulator = False
            , wasLoaded = True
        }

    else
        model


socketHandler : WebSocket.Response -> FunnelState -> Model -> ( Model, Cmd Msg )
socketHandler response state mdl =
    let
        model =
            doIsLoaded
                { mdl
                    | state = state
                    , error = Nothing
                }
    in
    case response of
        WebSocket.MessageReceivedResponse { message } ->
            { model | log = ("Received \"" ++ message ++ "\"") :: model.log }
                |> withNoCmd

        WebSocket.ConnectedResponse _ ->
            { model | log = "Connected" :: model.log }
                |> withNoCmd

        WebSocket.ClosedResponse { code, wasClean, expected } ->
            { model
                | log =
                    ("Closed, " ++ closedString code wasClean expected)
                        :: model.log
            }
                |> withNoCmd

        WebSocket.ErrorResponse error ->
            { model | log = WebSocket.errorToString error :: model.log }
                |> withNoCmd

        _ ->
            model |> withNoCmd


closedString : WebSocket.ClosedCode -> Bool -> Bool -> String
closedString code wasClean expected =
    "code: "
        ++ WebSocket.closedCodeToString code
        ++ ", "
        ++ (if wasClean then
                "clean"

            else
                "not clean"
           )
        ++ ", "
        ++ (if expected then
                "expected"

            else
                "NOT expected"
           )



-- VIEW


b : String -> Html Msg
b string =
    Html.b [] [ text string ]


br : Html msg
br =
    Html.br [] []


docp : String -> Html Msg
docp string =
    p [] [ text string ]


view : Model -> Html Msg
view model =
    let
        isConnected =
            WebSocket.isConnected model.key model.state.socket
    in
    div
        [ style "width" "40em"
        , style "margin" "auto"
        , style "margin-top" "1em"
        , style "padding" "1em"
        , style "border" "solid"
        ]
        [ h1 [] [ text "PortFunnel.WebSocket Example" ]
        , p []
            [ input
                [ value model.send
                , onInput UpdateSend
                , size 50
                ]
                []
            , text " "
            , button
                [ onClick Send
                , disabled (not isConnected)
                ]
                [ text "Send" ]
            ]
        , p []
            [ b "url: "
            , input
                [ value model.url
                , onInput UpdateUrl
                , size 30
                , disabled isConnected
                ]
                []
            , text " "
            , if isConnected then
                button [ onClick Close ]
                    [ text "Close" ]

              else
                button [ onClick Connect ]
                    [ text "Connect" ]
            , br
            , b "use simulator: "
            , input
                [ type_ "checkbox"
                , onClick ToggleUseSimulator
                , checked model.useSimulator
                , disabled isConnected
                ]
                []
            , br
            , b "auto reopen: "
            , input
                [ type_ "checkbox"
                , onClick ToggleAutoReopen
                , checked <|
                    WebSocket.willAutoReopen
                        model.key
                        model.state.socket
                ]
                []
            ]
        , p [] <|
            List.concat
                [ [ b "Log:"
                  , br
                  ]
                , List.intersperse br (List.map text model.log)
                ]
        , div []
            [ b "Instructions:"
            , docp <|
                "Fill in the 'url' and click 'Connect' to connect to a real server."
                    ++ " This will only work if you've connected the port JavaScript code."
            , docp "Fill in the text and click 'Send' to send a message."
            , docp "Click 'Close' to close the connection."
            , docp <|
                "If the 'use simulator' checkbox is checked at startup,"
                    ++ " then you're either runing from 'elm reactor' or"
                    ++ " the JavaScript code got an error starting."
            , docp <|
                "Uncheck the 'auto reopen' checkbox to report when the"
                    ++ " connection is lost unexpectedly, rather than the deault"
                    ++ " of attempting to reconnect."
            ]
        , p []
            [ b "Package: "
            , a [ href "https://package.elm-lang.org/packages/billstclair/elm-websocket-client/latest" ]
                [ text "billstclair/elm-websocket-client" ]
            , br
            , b "GitHub: "
            , a [ href "https://github.com/billstclair/elm-websocket-client" ]
                [ text "github.com/billstclair/elm-websocket-client" ]
            ]
        ]
