port module Main exposing (main)

{-| Very simple test app for the port code.

    `elm make src/simple.elm --output site/index.js`

-}

import Browser
import Cmd.Extra exposing (withCmd, withNoCmd)
import Html exposing (Html, a, button, div, h1, input, p, text)
import Html.Attributes exposing (href, size, value)
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


port webSocketClientCmd : Value -> Cmd msg


port webSocketClientSub : (Value -> msg) -> Sub msg


port parse : String -> Cmd msg


port parseReturn : (Value -> msg) -> Sub msg


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ webSocketClientSub Receive
        , parseReturn Process
        ]



-- MODEL


type alias Model =
    { send : String
    , log : List String
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


bytesQueuedJson : String
bytesQueuedJson =
    String.trim
        """
         {"tag": "bytesQueued", "args": {"key": "foo"}}
        """


exampleJsons : List String
exampleJsons =
    [ sendJson, bytesQueuedJson, closeJson, openJson ]


init : () -> ( Model, Cmd Msg )
init flags =
    { send = openJson
    , log = []
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
            { model
                | log = ("send: " ++ JE.encode 0 value) :: model.log
            }
                |> withCmd (webSocketClientCmd value)

        Receive value ->
            let
                log =
                    ("recv: " ++ JE.encode 0 value) :: model.log
            in
            { model | log = log } |> withNoCmd



-- VIEW


b : String -> Html msg
b string =
    Html.b [] [ text string ]


br : Html msg
br =
    Html.br [] []


sendSample : String -> Html Msg
sendSample sample =
    a [ onClick <| UpdateSend sample ]
        [ text sample ]


view : Model -> Html Msg
view model =
    div []
        [ h1 [] [ text "WebSocketClient Test Console" ]
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
        , p [] <|
            List.concat
                [ [ b "Sample messages (click to copy):"
                  , br
                  ]
                , List.intersperse br <| List.map sendSample exampleJsons
                ]
        , p [] <|
            List.concat
                [ [ b "Log:", br ]
                , List.intersperse br (List.map text model.log)
                ]
        ]
