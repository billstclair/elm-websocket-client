module Main exposing (main)

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
import Html exposing (Html, button, div, input, text)
import Html.Attributes exposing (size, value)
import Html.Events exposing (onClick, onInput)
import WebSocket


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


subscriptions : Model -> Sub Msg
subscriptions model =
    --Sub.none
    WebSocket.listen url Receive



-- MODEL


url : String
url =
    "ws://echo.websocket.org"


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
    | Receive String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateSend send ->
            ( { model | send = send }, Cmd.none )

        Send ->
            ( model
            , --Cmd.none
              WebSocket.send url model.send
            )

        Receive receive ->
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
            [ b "Received: "
            , text model.receive
            ]
        ]
