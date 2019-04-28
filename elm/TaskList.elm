module TaskList exposing (ExpandedTask, Filter(..), Msg(..), NewTaskField, ViewState(..), defaultView, dynamicSliderThumbCss, extractDate, extractSliderInput, filterName, onEnter, progressSlider, routeView, timingInfo, update, view, viewControls, viewControlsClear, viewControlsCount, viewControlsFilters, viewInput, viewKeyedTask, viewTask, viewTasks, visibilitySwap)

import AppData exposing (..)
import Browser
import Browser.Dom
import Css exposing (..)
import Date
import Environment exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (..)
import Html.Styled.Events exposing (..)
import Html.Styled.Keyed as Keyed
import Html.Styled.Lazy exposing (lazy, lazy2)
import Json.Decode as OldDecode
import Json.Decode.Exploration as Decode
import Json.Decode.Exploration.Pipeline as Pipeline exposing (..)
import Json.Encode as Encode exposing (..)
import Json.Encode.Extra as Encode2 exposing (..)
import Porting exposing (..)
import Task as Job
import Task.Progress exposing (..)
import Task.Task exposing (..)
import Task.TaskMoment exposing (..)
import Time
import Url.Parser as P exposing ((</>), Parser, fragment, int, map, oneOf, s, string)
import VirtualDom



--            MM    MM  OOOOO  DDDDD   EEEEEEE LL
--            MMM  MMM OO   OO DD  DD  EE      LL
--            MM MM MM OO   OO DD   DD EEEEE   LL
--            MM    MM OO   OO DD   DD EE      LL
--            MM    MM  OOOO0  DDDDDD  EEEEEEE LLLLLLL


type Filter
    = AllTasks
    | IncompleteTasksOnly
    | CompleteTasksOnly



--            :::     ::: ::::::::::: :::::::::: :::       :::
--            :+:     :+:     :+:     :+:        :+:       :+:
--            +:+     +:+     +:+     +:+        +:+       +:+
--            +#+     +:+     +#+     +#++:++#   +#+  +:+  +#+
--             +#+   +#+      +#+     +#+        +#+ +#+#+ +#+
--              #+#+#+#       #+#     #+#         #+#+# #+#+#
--                ###     ########### ##########   ###   ###


type ViewState
    = Normal (List Filter) (Maybe ExpandedTask) NewTaskField


routeView : Parser (ViewState -> a) a
routeView =
    P.map (Normal [ IncompleteTasksOnly ] Nothing "Test") (s "tasks")


defaultView : ViewState
defaultView =
    Normal [ AllTasks ] Nothing ""


type alias ExpandedTask =
    TaskId


type alias NewTaskField =
    String


view : ViewState -> AppData -> Environment -> Html Msg
view state app env =
    case state of
        Normal filters expanded field ->
            div
                [ class "todomvc-wrapper", css [ visibility Css.hidden ] ]
                [ section
                    [ class "todoapp" ]
                    [ lazy viewInput field
                    , Html.Styled.Lazy.lazy3 viewTasks env.time (Maybe.withDefault AllTasks (List.head filters)) app.tasks
                    , lazy2 viewControls filters app.tasks
                    ]
                , section [ css [ opacity (num 0.1) ] ]
                    [ text "Everything working well? Good."
                    ]
                ]



-- viewInput : String -> Html Msg


viewInput : String -> Html Msg
viewInput task =
    header
        [ class "header" ]
        [ h1 [] [ text "docket" ]
        , input
            [ class "new-task"
            , placeholder "What needs to be done?"
            , autofocus True
            , value task
            , name "newTask"
            , onInput UpdateNewEntryField
            , onEnter Add
            ]
            []
        ]


onEnter : Msg -> Attribute Msg
onEnter msg =
    let
        isEnter code =
            if code == 13 then
                OldDecode.succeed msg

            else
                OldDecode.fail "not ENTER"
    in
    on "keydown" (OldDecode.andThen isEnter keyCode)



-- VIEW ALL TODOS
-- viewTasks : String -> List Task -> Html Msg


viewTasks : Moment -> Filter -> List Task -> Html Msg
viewTasks now filter tasks =
    let
        isVisible task =
            case filter of
                CompleteTasksOnly ->
                    completed task

                IncompleteTasksOnly ->
                    not (completed task)

                _ ->
                    True

        allCompleted =
            List.all completed tasks
    in
    section
        [ class "main" ]
        [ input
            [ class "toggle-all"
            , type_ "checkbox"
            , name "toggle"
            , Html.Styled.Attributes.checked allCompleted
            ]
            []
        , label
            [ for "toggle-all" ]
            [ text "Mark all as complete" ]
        , Keyed.ul [ class "task-list" ] <|
            List.map (viewKeyedTask now) (List.filter isVisible tasks)
        ]



-- VIEW INDIVIDUAL ENTRIES


viewKeyedTask : Moment -> Task -> ( String, Html Msg )
viewKeyedTask now task =
    ( String.fromInt task.id, lazy2 viewTask now task )



-- viewTask : Task -> Html Msg


viewTask : Moment -> Task -> Html Msg
viewTask now task =
    li
        [ class "task-entry", classList [ ( "completed", completed task ), ( "editing", task.editing ) ] ]
        [ progressSlider task
        , div
            [ class "view" ]
            [ input
                [ class "toggle"
                , type_ "checkbox"
                , Html.Styled.Attributes.checked (completed task)
                , onClick
                    (UpdateProgress task.id
                        (if not (completed task) then
                            maximize task.completion

                         else
                            setPortion task.completion 0
                        )
                    )
                ]
                []
            , label
                [ onDoubleClick (EditingTitle task.id True), onClick (FocusSlider task.id True) ]
                [ text task.title ]
            , div
                [ class "timing-info" ]
                [ timingInfo now task ]
            , button
                [ class "destroy"
                , onClick (Delete task.id)
                ]
                [ text "×" ]
            ]
        , input
            [ class "edit"
            , value task.title
            , name "title"
            , id ("task-" ++ String.fromInt task.id)
            , onInput (UpdateTask task.id)
            , onBlur (EditingTitle task.id False)
            , onEnter (EditingTitle task.id False)
            ]
            []
        , div [ class "task-drawer", Html.Styled.Attributes.hidden False ]
            [ label [ for "readyDate" ] [ text "Ready" ]
            , input [ type_ "date", name "readyDate", onInput (extractDate task.id "Ready"), pattern "[0-9]{4}-[0-9]{2}-[0-9]{2}" ] []
            , label [ for "startDate" ] [ text "Start" ]
            , input [ type_ "date", name "startDate", onInput (extractDate task.id "Start"), pattern "[0-9]{4}-[0-9]{2}-[0-9]{2}" ] []
            , label [ for "finishDate" ] [ text "Finish" ]
            , input [ type_ "date", name "finishDate", onInput (extractDate task.id "Finish"), pattern "[0-9]{4}-[0-9]{2}-[0-9]{2}" ] []
            , label [ for "deadlineDate" ] [ text "Deadline" ]
            , input [ type_ "date", name "deadlineDate", onInput (extractDate task.id "Deadline"), pattern "[0-9]{4}-[0-9]{2}-[0-9]{2}" ] []
            , label [ for "expiresDate" ] [ text "Expires" ]
            , input [ type_ "date", name "expiresDate", onInput (extractDate task.id "Expires"), pattern "[0-9]{4}-[0-9]{2}-[0-9]{2}" ] []
            ]
        ]


{-| This slider is an html input type=range so it does most of the work for us. (It's accessible, works with arrow keys, etc.) No need to make our own ad-hoc solution! We theme it to look less like a form control, and become the background of our Task entry.
-}
progressSlider : Task -> Html Msg
progressSlider task =
    input
        [ class "task-progress"
        , type_ "range"
        , value <| String.fromInt <| getPortion task.completion
        , Html.Styled.Attributes.min "0"
        , Html.Styled.Attributes.max <| String.fromInt <| getWhole task.completion
        , step
            (if isDiscrete <| getUnits task.completion then
                "1"

             else
                "any"
            )
        , onInput (extractSliderInput task)
        , onDoubleClick (EditingTitle task.id True)
        , onFocus (FocusSlider task.id True)
        , onBlur (FocusSlider task.id False)
        , dynamicSliderThumbCss (getNormalizedPortion task.completion)
        ]
        []


{-| The Slider has a thumb control that we push outside of the box, and shape it kinda like a pin, like the text selector on Android. Unfortunately, it expects the track to have side margins, so it only bumps up against the edges and doesn't line up with the actual progress since the track has been stretched to not have these standard margins.

Rather than force the thumb to push past the walls, I came up with this cool-looking way to warp the tip of the pin to always line up correctly. The pin is rotated more or less than the original 45deg (center) based on the progress being more or less than 50%.

Also, since this caused the thumb to appear to float a few pixels higher when at extreme rotations, I added a small linear offset to make it line up better. This is technically still wrong, TODO it should be a trigonometric offset (sin/cos) since rotation is causing the need for it.

-}
dynamicSliderThumbCss : Float -> Attribute msg
dynamicSliderThumbCss portion =
    let
        ( angle, offset ) =
            ( portion * -90, abs ((portion - 0.5) * 5) )
    in
    css [ focus [ pseudoElement "-moz-range-thumb" [ transforms [ translateY (px (-50 + offset)), rotate (deg angle) ] ] ] ]


extractSliderInput : Task -> String -> Msg
extractSliderInput task input =
    UpdateProgress task.id <|
        setPortion task.completion <|
            Maybe.withDefault 0 <|
                String.toInt input


{-| Human-friendly text in a task summarizing the various TaskMoments (e.g. the due date)
TODO currently only captures deadline
TODO doesn't specify "ago", "in", etc.
-}
timingInfo : Time.Posix -> Task -> Html Msg
timingInfo time task =
    text <| describeTaskMoment time task.deadline


{-| Get the date out of a date input.
TODO handle LocalMoments and UniversalMoments
TODO handle times
-}
extractDate : TaskId -> String -> String -> Msg
extractDate task field input =
    case Date.fromIsoString input of
        Ok date ->
            UpdateTaskDate task field (LocalDate date)

        Err msg ->
            NoOp


viewControls : List Filter -> List Task -> Html Msg
viewControls visibilityFilters tasks =
    let
        tasksCompleted =
            List.length (List.filter completed tasks)

        tasksLeft =
            List.length tasks - tasksCompleted
    in
    footer
        [ class "footer"
        , Html.Styled.Attributes.hidden (List.isEmpty tasks)
        ]
        [ Html.Styled.Lazy.lazy viewControlsCount tasksLeft
        , Html.Styled.Lazy.lazy viewControlsFilters visibilityFilters
        , Html.Styled.Lazy.lazy viewControlsClear tasksCompleted
        ]


viewControlsCount : Int -> Html msg
viewControlsCount tasksLeft =
    let
        item_ =
            if tasksLeft == 1 then
                " item"

            else
                " items"
    in
    span
        [ class "task-count" ]
        [ strong [] [ text (String.fromInt tasksLeft) ]
        , text (item_ ++ " left")
        ]


viewControlsFilters : List Filter -> Html Msg
viewControlsFilters visibilityFilters =
    ul
        [ class "filters" ]
        [ visibilitySwap "#/" AllTasks visibilityFilters
        , text " "
        , visibilitySwap "#/active" IncompleteTasksOnly visibilityFilters
        , text " "
        , visibilitySwap "#/completed" CompleteTasksOnly visibilityFilters
        ]


visibilitySwap : String -> Filter -> List Filter -> Html Msg
visibilitySwap uri visibilityToDisplay actualVisibility =
    li
        []
        [ a [ href uri, classList [ ( "selected", List.member visibilityToDisplay actualVisibility ) ] ]
            [ text (filterName visibilityToDisplay) ]
        ]


filterName : Filter -> String
filterName filter =
    case filter of
        AllTasks ->
            "All"

        CompleteTasksOnly ->
            "Complete"

        IncompleteTasksOnly ->
            "Remaining"



-- viewControlsClear : Int -> VirtualDom.Node Msg


viewControlsClear : Int -> Html Msg
viewControlsClear tasksCompleted =
    button
        [ class "clear-completed"
        , Html.Styled.Attributes.hidden (tasksCompleted == 0)
        , onClick DeleteComplete
        ]
        [ text ("Clear completed (" ++ String.fromInt tasksCompleted ++ ")")
        ]



--             _   _ ______ ______   ___   _____  _____
--            | | | || ___ \|  _  \ / _ \ |_   _||  ___|
--            | | | || |_/ /| | | |/ /_\ \  | |  | |__
--            | | | ||  __/ | | | ||  _  |  | |  |  __|
--            | |_| || |    | |/ / | | | |  | |  | |___
--             \___/ \_|    |___/  \_| |_/  \_/  \____/


type Msg
    = EditingTitle TaskId Bool
    | UpdateTask TaskId String
    | Add
    | Delete TaskId
    | DeleteComplete
    | UpdateProgress TaskId Progress
    | FocusSlider TaskId Bool
    | UpdateTaskDate TaskId String TaskMoment
    | UpdateNewEntryField String
    | NoOp


update : Msg -> ViewState -> AppData -> Environment -> ( ViewState, AppData, Cmd Msg )
update msg state app env =
    case msg of
        Add ->
            case state of
                Normal filters _ "" ->
                    ( Normal filters Nothing ""
                      -- resets new-entry-textbox to empty, collapses tasks
                    , app
                    , Cmd.none
                    )

                Normal filters _ newTaskTitle ->
                    ( Normal filters Nothing ""
                      -- resets new-entry-textbox to empty, collapses tasks
                    , { app
                        | tasks = app.tasks ++ [ newTask newTaskTitle (Time.posixToMillis env.time) ]
                      }
                      -- now using the creation time as the task ID, for sync
                    , Cmd.none
                    )

        UpdateNewEntryField typedSoFar ->
            ( let
                (Normal filters expanded _) =
                    state
              in
              Normal filters expanded typedSoFar
              -- TODO will collapse expanded tasks. Should it?
            , app
            , Cmd.none
            )

        EditingTitle id isEditing ->
            let
                updateTask t =
                    if t.id == id then
                        { t | editing = isEditing }
                        -- TODO editing should be a viewState thing, not a task prop

                    else
                        t

                focus =
                    Browser.Dom.focus ("task-" ++ String.fromInt id)
            in
            ( state
            , { app | tasks = List.map updateTask app.tasks }
            , Job.attempt (\_ -> NoOp) focus
            )

        UpdateTask id task ->
            let
                updateTask t =
                    if t.id == id then
                        { t | title = task }

                    else
                        t
            in
            ( state
            , { app | tasks = List.map updateTask app.tasks }
            , Cmd.none
            )

        UpdateTaskDate id field date ->
            let
                updateTask t =
                    if t.id == id then
                        { t | deadline = date }

                    else
                        t
            in
            ( state
            , { app | tasks = List.map updateTask app.tasks }
            , Cmd.none
            )

        Delete id ->
            ( state
            , { app | tasks = List.filter (\t -> t.id /= id) app.tasks }
            , Cmd.none
            )

        DeleteComplete ->
            ( state
            , { app | tasks = List.filter (not << completed) app.tasks }
            , Cmd.none
            )

        UpdateProgress id new_completion ->
            let
                updateTask t =
                    if t.id == id then
                        { t | completion = new_completion }

                    else
                        t
            in
            ( state
            , { app | tasks = List.map updateTask app.tasks }
            , Cmd.none
            )

        FocusSlider task focused ->
            ( state
            , app
            , Cmd.none
            )

        NoOp ->
            ( state
            , app
            , Cmd.none
            )