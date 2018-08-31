port module Main exposing (main)

{-| Very simple test app for the port code.

    `elm make src/simple.elm --output site/index.js`

-}

import Browser
import Html exposing (Html, button, div, input, p, text)
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


subscriptions : Model -> Sub Msg
subscriptions model =
    jsToWebSocketClient Receive



-- MODEL


type alias Model =
    { send : String
    , receive : String
    }


init : () -> ( Model, Cmd Msg )
init flags =
    ( { send = "Hello World!"
      , receive = ""
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = UpdateSend String
    | Send
    | Receive Value


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateSend send ->
            ( { model | send = send }, Cmd.none )

        Send ->
            ( model
            , webSocketClientToJs <| JE.string model.send
            )

        Receive value ->
            let
                receive =
                    JE.encode 0 value
            in
            ( { model | receive = receive }
            , Cmd.none
            )



-- VIEW


b : String -> Html Msg
b string =
    Html.b [] [ text string ]


view : Model -> Html Msg
view model =
    div []
        [ div []
            [ input
                [ value model.send
                , onInput UpdateSend
                , size 50
                ]
                []
            , text " "
            , button [ onClick Send ] [ text "Send" ]
            ]
        , div []
            [ p []
                [ text model.receive ]
            ]
        ]
