port module Main exposing (main)

{-| WebSocketClient Example
-}

import Browser
import Cmd.Extra exposing (addCmd, addCmds, withCmd, withCmds, withNoCmd)
import Dict exposing (Dict)
import Html exposing (Html, a, button, div, h1, input, p, span, text)
import Html.Attributes exposing (disabled, href, size, style, value)
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
    , funnelState : FunnelState
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


init : () -> ( Model, Cmd Msg )
init _ =
    { send = "Hello World!"
    , log = []
    , url = defaultUrl
    , useSimulator = True
    , funnelState = { socket = WebSocket.initialState }
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
          , SocketFunnel <|
                FunnelSpec socketAccessors
                    WebSocket.moduleDesc
                    WebSocket.commander
                    socketHandler
          )
        ]



-- UPDATE


type Msg
    = UpdateSend String
    | UpdateUrl String
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
            case PortFunnel.decodeGenericMessage value of
                Err error ->
                    { model | error = Just error } |> withNoCmd

                Ok genericMessage ->
                    let
                        moduleName =
                            genericMessage.moduleName
                    in
                    case Dict.get moduleName funnels of
                        Just funnel ->
                            case funnel of
                                SocketFunnel appFunnel ->
                                    let
                                        ( mdl, cmd ) =
                                            process genericMessage appFunnel model
                                    in
                                    if
                                        mdl.useSimulator
                                            && WebSocket.isLoaded
                                                mdl.funnelState.socket
                                    then
                                        { mdl | useSimulator = False }
                                            |> withCmd cmd

                                    else
                                        mdl |> withCmd cmd

                        _ ->
                            { model
                                | error =
                                    Just <|
                                        "Unknown moduleName: "
                                            ++ moduleName
                            }
                                |> withNoCmd


process : GenericMessage -> AppFunnel substate message response -> Model -> ( Model, Cmd Msg )
process genericMessage funnel model =
    case
        PortFunnel.appProcess (getCmdPort model)
            genericMessage
            funnel
            model.funnelState
            model
    of
        Err error ->
            { model | error = Just error } |> withNoCmd

        Ok ( model2, cmd ) ->
            model2 |> withCmd cmd


send : Model -> WebSocket.Message -> Cmd Msg
send model message =
    WebSocket.send (getCmdPort model) message


socketHandler : WebSocket.Response -> FunnelState -> Model -> ( Model, Cmd Msg )
socketHandler response state mdl =
    let
        model =
            { mdl
                | funnelState = state
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
            WebSocket.isConnected model.key model.funnelState.socket
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
