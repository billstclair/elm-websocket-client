port module Main exposing (main)

{-| WebSocket example

Does not build if `WebSocket.listen` or `WebSocket.send` are called.
DOES build and run if you replace those calls with `Sub.none` and
`Cmd.none`, respectively (as in the commented lines above them).

    `elm make src/Main.elm`

Gets the "Map.!: given key is not an element in the map" error, as in
<https://github.com/elm/compiler/issues/1753>.

It sure would be nice to have a build with profiling, so that I could see a
full stack backtrace of the error with:

    `elm +RTS -xc make src/Main.elm`

There is a working 0.18 example, including a `Main.elm` that is
identical to this one, except for 0.19 changes, in
<https://github.com/billstclair/elm-websocket-example>.

-}

import Browser
import Html exposing (Html, a, button, div, h1, input, p, span, text)
import Html.Attributes exposing (disabled, href, size, style, value)
import Html.Events exposing (onClick, onInput)
import Json.Encode exposing (Value)
import WebSocketClient
    exposing
        ( ClosedCode(..)
        , Config
        , Error(..)
        , Response(..)
        , State
        , close
        , closedCodeToString
        , errorToString
        , makeConfig
        , makeSimulatorConfig
        , makeState
        , open
        , process
        , send
        )


port webSocketClientCmd : Value -> Cmd msg


port webSocketClientSub : (Value -> msg) -> Sub msg


simulatorConfig : Config Msg
simulatorConfig =
    makeSimulatorConfig Just


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


subscriptions : Model -> Sub Msg
subscriptions model =
    webSocketClientSub Receive



-- MODEL


defaultUrl : String
defaultUrl =
    "wss://echo.websocket.org"


type alias Model =
    { send : String
    , log : List String
    , url : String
    , state : State Msg
    , config : Maybe (Config Msg)
    , key : String
    }


init : () -> ( Model, Cmd Msg )
init flags =
    ( { send = "Hello World!"
      , log = []
      , url = defaultUrl
      , state = makeState simulatorConfig
      , config = Nothing
      , key = ""
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = UpdateSend String
    | UpdateUrl String
    | Connect
    | Simulate
    | Close
    | Send
    | Receive Value


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateSend send ->
            ( { model | send = send }, Cmd.none )

        UpdateUrl url ->
            ( { model | url = url }, Cmd.none )

        Connect ->
            connect
                { model
                    | log =
                        ("Connecting to " ++ model.url) :: model.log
                }
            <|
                makeConfig webSocketClientCmd

        Simulate ->
            connect
                { model
                    | log =
                        "Connecting to simulator" :: model.log
                }
            <|
                simulatorConfig

        Send ->
            processResponse
                { model
                    | log =
                        ("Sending \"" ++ model.send ++ "\"") :: model.log
                }
            <|
                send model.state model.key model.send

        Receive value ->
            processResponse model <| process model.state value

        Close ->
            processResponse
                { model
                    | config = Nothing
                    , log = "Closing" :: model.log
                }
            <|
                close model.state model.key


connect : Model -> Config Msg -> ( Model, Cmd Msg )
connect model config =
    let
        m =
            { model
                | state = makeState config
                , config = Just config
                , key = model.url
            }
    in
    processResponse m <| open m.state m.url


processResponse : Model -> ( State Msg, Response Msg ) -> ( Model, Cmd Msg )
processResponse model ( state, response ) =
    let
        mdl =
            { model | state = state }
    in
    case response of
        NoResponse ->
            ( mdl, Cmd.none )

        CmdResponse cmd ->
            ( mdl, cmd )

        MessageReceivedResponse { message } ->
            ( { mdl | log = ("Received \"" ++ message ++ "\"") :: mdl.log }
            , Cmd.none
            )

        ConnectedResponse { key, description } ->
            ( { mdl | log = "Connected" :: mdl.log }
            , Cmd.none
            )

        ClosedResponse { code, wasClean, expected } ->
            ( { mdl
                | config = Nothing
                , log =
                    ("Closed, " ++ closedString code wasClean expected)
                        :: mdl.log
              }
            , Cmd.none
            )

        ErrorResponse error ->
            ( { mdl | log = errorToString error :: model.log }
            , Cmd.none
            )


closedString : ClosedCode -> Bool -> Bool -> String
closedString code wasClean expected =
    "code: "
        ++ closedCodeToString code
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
            model.config /= Nothing
    in
    div
        [ style "width" "40em"
        , style "margin" "auto"
        , style "margin-top" "1em"
        , style "padding" "1em"
        , style "border" "solid"
        ]
        [ h1 [] [ text "WebSocketClient Example" ]
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
                span []
                    [ button [ onClick Connect ]
                        [ text "Connect" ]
                    , text " "
                    , button [ onClick Simulate ]
                        [ text "Simulate" ]
                    ]
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
            , docp <|
                "Click 'Simulate' to connect to a simulated echo server."
                    ++ " This will work in 'elm reactor'."
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
