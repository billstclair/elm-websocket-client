port module Main exposing (main)

{-| Very simple test app for the port code.

    `elm make src/simple.elm --output site/index.js`

-}

import Browser
import Cmd.Extra exposing (withCmd, withNoCmd)
import Html exposing (Html, button, div, h1, input, p, text)
import Html.Attributes exposing (size, value)
import Html.Events exposing (onClick, onInput)
import Json.Decode as JD
import Json.Encode as JE exposing (Value)


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


port webSocketClientToJs : Value -> Cmd msg


port jsToWebSocketClient : (Value -> msg) -> Sub msg


port parse : String -> Cmd msg


port parseReturn : (Value -> msg) -> Sub msg


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ jsToWebSocketClient Receive
        , parseReturn Process
        ]



-- MODEL


type alias Model =
    { send : String
    , receive : List String
    }


openJson : String
openJson =
    String.trim
        """
         {"tag": "open", "args": {"key": "foo", "url": "wss://echo.websocket.org"}}
        """


sendJson : String
sendJson =
    String.trim
        """
       {"tag": "send", "args": {"key": "foo", "message": "Hello, World!"}}
      """


closeJson : String
closeJson =
    String.trim
        """
         {"tag": "close", "args": {"key": "foo", "reason": "Just because."}}
        """


init : () -> ( Model, Cmd Msg )
init flags =
    { send = openJson
    , receive = []
    }
        |> withNoCmd



-- UPDATE


type Msg
    = UpdateSend String
    | Send
    | Process Value
    | Receive Value


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateSend send ->
            { model | send = send } |> withNoCmd

        Send ->
            model |> withCmd (parse model.send)

        Process value ->
            model |> withCmd (webSocketClientToJs value)

        Receive value ->
            let
                receive =
                    JE.encode 0 value :: model.receive
            in
            { model | receive = receive } |> withNoCmd



-- VIEW


b : String -> Html msg
b string =
    Html.b [] [ text string ]


br : Html msg
br =
    Html.br [] []


view : Model -> Html Msg
view model =
    div []
        [ h1 [] [ text "WebSocket Test Console" ]
        , p []
            [ input
                [ value model.send
                , onInput UpdateSend
                , size 100
                ]
                []
            , text " "
            , button [ onClick Send ] [ text "Send" ]
            ]
        , p []
            [ b "Sample messages:"
            , br
            , text sendJson
            , br
            , text closeJson
            , br
            , text openJson
            ]
        , p [] <|
            List.concat
                [ [ b "Received:", br ]
                , List.intersperse br (List.map text model.receive)
                ]
        ]
