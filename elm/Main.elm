port module Main exposing (JsonAppDatabase, Model, Msg(..), Screen(..), ViewState, appDataFromJson, appDataToJson, buildModel, defaultView, emptyViewState, infoFooter, init, main, setStorage, subscriptions, update, updateWithStorage, updateWithTime, view, viewUrl)

--import Time.DateTime as Moment exposing (DateTime, dateTime, year, month, day, hour, minute, second, millisecond)
--import Time.TimeZones as TimeZones
--import Time.ZonedDateTime as LocalMoment exposing (ZonedDateTime)

import AppData exposing (..)
import Browser
import Browser.Dom as Dom
import Browser.Navigation as Nav exposing (..)
import Environment exposing (..)
import External.Commands exposing (..)
import Html.Styled as H exposing (..)
import Html.Styled.Attributes exposing (..)
import Html.Styled.Events exposing (..)
import Json.Decode.Exploration as Decode exposing (..)
import Json.Encode as Encode
import Task as Job
import Task.Progress exposing (..)
import Task.TaskMoment exposing (..)
import TaskList
import Time
import TimeTracker exposing (..)
import Url
import Url.Parser as P exposing ((</>), Parser, int, map, oneOf, s, string)


main : Program (Maybe JsonAppDatabase) Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = updateWithTime
        , subscriptions = subscriptions
        , onUrlChange = NewUrl
        , onUrlRequest = Link
        }


subscriptions : Model -> Sub Msg
subscriptions model =
    Time.every (60 * 1000) MinutePassed


port setStorage : JsonAppDatabase -> Cmd msg


{-| We want to `setStorage` on every update. This function adds the setStorage
command for every step of the update function.
-}
updateWithStorage : Msg -> Model -> ( Model, Cmd Msg )
updateWithStorage msg model =
    let
        ( newModel, cmds ) =
            update msg model
    in
    ( newModel
    , Cmd.batch [ setStorage (appDataToJson newModel.appData), cmds ]
    )


{-| Slips in before the real `update` function to pass in the current time.

For bookkeeping purposes, we want the current time for pretty much every update. This function intercepts the `update` process by first updating our model's `time` field before passing our Msg along to the real `update` function, which can then assume `model.time` is an up-to-date value.

(Since Elm is pure and Time is side-effect-y, there's no better way to do this.)
<https://stackoverflow.com/a/41025989/8645412>

-}
updateWithTime : Msg -> Model -> ( Model, Cmd Msg )
updateWithTime msg ({ environment } as model) =
    case msg of
        NoOp ->
            ( model
            , Cmd.none
            )

        -- first get the current time
        Tick submsg ->
            ( model
            , Job.perform (Tock submsg) Time.now
            )

        -- actually do the update
        Tock submsg time ->
            let
                newEnv =
                    { environment | time = time }
            in
            updateWithStorage submsg { model | environment = newEnv }

        -- intercept normal update
        otherMsg ->
            updateWithTime (Tick msg) model


{-| TODO: The "ModelAsJson" could be a whole slew of flags instead.
Key and URL also need to be fed into the model.
-}
init : Maybe JsonAppDatabase -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init maybeJson url key =
    let
        startingModel =
            case maybeJson of
                Just jsonAppDatabase ->
                    case appDataFromJson jsonAppDatabase of
                        Success savedAppData ->
                            buildModel savedAppData url key

                        WithWarnings warnings savedAppData ->
                            buildModel (AppData.saveWarnings savedAppData warnings) url key

                        Errors errors ->
                            buildModel (AppData.saveErrors AppData.fromScratch errors) url key

                        BadJson ->
                            buildModel AppData.fromScratch url key

                -- no json stored at all
                Nothing ->
                    buildModel AppData.fromScratch url key

        environment =
            Environment

        effects =
            [ Job.perform MinutePassed Time.now
            , Job.perform SetZone Time.here
            ]
    in
    ( startingModel
    , Cmd.batch effects
    )



--            MM    MM  OOOOO  DDDDD   EEEEEEE LL
--            MMM  MMM OO   OO DD  DD  EE      LL
--            MM MM MM OO   OO DD   DD EEEEE   LL
--            MM    MM OO   OO DD   DD EE      LL
--            MM    MM  OOOO0  DDDDDD  EEEEEEE LLLLLLL


{-| Our whole app's Model.
Intentionally minimal - we originally went with the common elm habit of stuffing any and all kinds of 'state' into the model, but we find it cleaner to separate the _"real" state_ (transient stuff, e.g. "dialog box is open", all stored in the page's URL (`viewState`)) from _"application data"_ (e.g. "task is due thursday", all stored in App "Database").
-}
type alias Model =
    { viewState : ViewState
    , appData : AppData
    , environment : Environment
    }


buildModel : AppData -> Url.Url -> Nav.Key -> Model
buildModel appData url key =
    { viewState = viewUrl url
    , appData = appData
    , environment = Environment.preInit key
    }


type alias JsonAppDatabase =
    String


appDataFromJson : JsonAppDatabase -> DecodeResult AppData
appDataFromJson incomingJson =
    Decode.decodeString decodeAppData incomingJson


appDataToJson : AppData -> JsonAppDatabase
appDataToJson appData =
    Encode.encode 0 (encodeAppData appData)


type alias ViewState =
    { primaryView : Screen
    , uid : Int
    }


emptyViewState : ViewState
emptyViewState =
    { primaryView = TimeTracker TimeTracker.defaultView
    , uid = 0
    }


type Screen
    = TaskList TaskList.ViewState
    | TimeTracker TimeTracker.ViewState
    | Calendar
    | Features
    | Preferences


screenToViewState : Screen -> ViewState
screenToViewState screen =
    { primaryView = screen, uid = 0 }



--            :::     ::: ::::::::::: :::::::::: :::       :::
--            :+:     :+:     :+:     :+:        :+:       :+:
--            +:+     +:+     +:+     +:+        +:+       +:+
--            +#+     +:+     +#+     +#++:++#   +#+  +:+  +#+
--             +#+   +#+      +#+     +#+        +#+ +#+#+ +#+
--              #+#+#+#       #+#     #+#         #+#+# #+#+#
--                ###     ########### ##########   ###   ###


defaultView : ViewState
defaultView =
    ViewState (TimeTracker TimeTracker.defaultView) 0


view : Model -> Browser.Document Msg
view { viewState, appData, environment } =
    case viewState.primaryView of
        TaskList subState ->
            { title = "Docket - which page"
            , body =
                List.map toUnstyled
                    [ H.map TaskListMsg (TaskList.view subState appData environment)
                    , infoFooter
                    , errorList appData.errors
                    ]
            }

        TimeTracker subState ->
            { title = "Docket Time Tracker"
            , body =
                List.map toUnstyled
                    [ H.map TimeTrackerMsg (TimeTracker.view subState appData environment)
                    , infoFooter
                    , errorList appData.errors
                    ]
            }

        _ ->
            { title = "TODO Some other page"
            , body = List.map toUnstyled [ infoFooter ]
            }



-- myStyle = (style, "color:red")
--
-- div [(att1, "hi"), (att2, "yo"), (myStyle completion)] [nodes]
--
-- <div att1="hi" att2="yo">nodes</div>


infoFooter : Html Msg
infoFooter =
    footer [ class "info" ]
        [ p [] [ text "Double-click to edit a task" ]
        , p []
            [ text "Written by "
            , a [ href "https://github.com/Erudition" ] [ text "Erudition" ]
            ]
        , p []
            [ text "(Increasingly more distant) fork of Evan's elm "
            , a [ href "http://todomvc.com" ] [ text "TodoMVC" ]
            ]
        ]


errorList : List String -> Html Msg
errorList stringList =
    let
        asLi desc =
            li [ onClick ClearErrors ] [ text desc ]
    in
    ol [] (List.map asLi stringList)



-- type Phrase = Written_by
--             | Double_click_to_edit_a_task
-- say : Phrase -> Language -> String
-- say phrase language =
--     ""
--             _   _ ______ ______   ___   _____  _____
--            | | | || ___ \|  _  \ / _ \ |_   _||  ___|
--            | | | || |_/ /| | | |/ /_\ \  | |  | |__
--            | | | ||  __/ | | | ||  _  |  | |  |  __|
--            | |_| || |    | |/ / | | | |  | |  | |___
--             \___/ \_|    |___/  \_| |_/  \_/  \____/


{-| Users of our app can trigger messages by clicking and typing. These
messages are fed into the `update` function as they occur, letting us react
to them.
-}
type Msg
    = NoOp
    | Tick Msg
    | Tock Msg Time.Posix
    | MinutePassed Moment
    | SetZone Time.Zone
    | ClearErrors
    | Link Browser.UrlRequest
    | NewUrl Url.Url
    | TaskListMsg TaskList.Msg
    | TimeTrackerMsg TimeTracker.Msg



-- How we update our Model on a given Msg?


update : Msg -> Model -> ( Model, Cmd Msg )
update msg ({ viewState, appData, environment } as model) =
    let
        justRunCommand command =
            ( model, command )

        justSetEnv newEnv =
            ( Model viewState appData newEnv, Cmd.none )
    in
    case ( msg, viewState.primaryView ) of
        ( NoOp, _ ) ->
            ( model, Cmd.none )

        ( MinutePassed time, _ ) ->
            justSetEnv { environment | time = time }

        ( SetZone zone, _ ) ->
            justSetEnv { environment | timeZone = zone }

        ( ClearErrors, _ ) ->
            ( Model viewState { appData | errors = [] } environment, Cmd.none )

        ( Link urlRequest, _ ) ->
            case urlRequest of
                Browser.Internal url ->
                    justRunCommand <| Nav.pushUrl environment.navkey (Url.toString url)

                Browser.External href ->
                    justRunCommand <| Nav.load href

        -- TODO should we also insert Nav command to hide extra stuff from address bar after nav, while still updating the viewState?
        ( NewUrl url, _ ) ->
            ( { model | viewState = viewUrl url }, Cmd.none )

        ( TaskListMsg subMsg, TaskList subViewState ) ->
            let
                ( newState, newApp, newCommand ) =
                    TaskList.update subMsg subViewState appData environment
            in
            ( Model (ViewState (TaskList newState) 0) newApp environment, Cmd.map TaskListMsg newCommand )

        ( TimeTrackerMsg subMsg, TimeTracker subViewState ) ->
            let
                ( newState, newApp, newCommand ) =
                    TimeTracker.update subMsg subViewState appData environment
            in
            ( Model (ViewState (TimeTracker newState) 0) newApp environment, Cmd.map TimeTrackerMsg newCommand )

        ( _, _ ) ->
            ( model, Cmd.none )



-- PARSER


viewUrl : Url.Url -> ViewState
viewUrl url =
    let
        parseIt finalUrl =
            Maybe.withDefault defaultView (P.parse routeParser finalUrl)
    in
    case ( url.path, url.fragment ) of
        ( "/index.html", Just containspath ) ->
            let
                simulatedUrl =
                    { url | path = containspath }
            in
            parseIt simulatedUrl

        ( _, _ ) ->
            parseIt url


routeParser : Parser (ViewState -> a) a
routeParser =
    let
        wrapScreen parser =
            P.map screenToViewState parser
    in
    oneOf
        [ wrapScreen (P.map TaskList TaskList.routeView)
        , wrapScreen (P.map TimeTracker TimeTracker.routeView)
        ]