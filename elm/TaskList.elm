module TaskList exposing (ExpandedTask, Filter(..), Msg(..), NewTaskField, ViewState(..), attemptDateChange, defaultView, dynamicSliderThumbCss, extractSliderInput, filterName, onEnter, progressSlider, routeView, timingInfo, update, urlTriggers, view, viewControls, viewControlsClear, viewControlsCount, viewControlsFilters, viewInput, viewKeyedTask, viewTask, viewTasks, visibilitySwap)

import Activity.Switching
import AppData exposing (..)
import Browser
import Browser.Dom
import Css exposing (..)
import Date
import Dict
import Environment exposing (..)
import External.Commands as Commands
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (..)
import Html.Styled.Events exposing (..)
import Html.Styled.Keyed as Keyed
import Html.Styled.Lazy exposing (lazy, lazy2)
import ID
import Incubator.IntDict.Extra as IntDict
import Incubator.Todoist as Todoist
import Incubator.Todoist.Command as TodoistCommand
import IntDict
import Integrations.Todoist
import Json.Decode as OldDecode
import Json.Decode.Exploration as Decode
import Json.Decode.Exploration.Pipeline as Pipeline exposing (..)
import Json.Encode as Encode exposing (..)
import Json.Encode.Extra as Encode2 exposing (..)
import List.Extra as List
import Porting exposing (..)
import SmartTime.Human.Calendar as Calendar exposing (CalendarDate)
import SmartTime.Human.Clock as Clock exposing (TimeOfDay)
import SmartTime.Human.Duration as HumanDuration exposing (HumanDuration)
import SmartTime.Human.Moment as HumanMoment exposing (FuzzyMoment(..), Zone)
import SmartTime.Moment as Moment exposing (Moment)
import String.Normalize
import Task as Job
import Task.Progress exposing (..)
import Task.Task as Task exposing (Instance)
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
    P.map (Normal [ IncompleteTasksOnly ] Nothing "") (P.s "tasks")


defaultView : ViewState
defaultView =
    Normal [ AllTasks ] Nothing ""


type alias ExpandedTask =
    Task.ClassID


type alias NewTaskField =
    String


view : ViewState -> AppData -> Environment -> Html Msg
view state app env =
    case state of
        Normal filters expanded field ->
            let
                activeFilter =
                    Maybe.withDefault AllTasks (List.head filters)

                allFullTaskInstances =
                    Task.buildFullInstanceDict ( app.taskEntries, app.taskClasses, app.taskInstances )

                sortedTasks =
                    Task.prioritize env.time env.timeZone <| IntDict.values allFullTaskInstances
            in
            div
                [ class "todomvc-wrapper", css [ visibility Css.hidden ] ]
                [ section
                    [ class "todoapp" ]
                    [ lazy viewInput field
                    , Html.Styled.Lazy.lazy3 viewTasks env activeFilter sortedTasks
                    , lazy2 viewControls filters (IntDict.values allFullTaskInstances)
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


viewTasks : Environment -> Filter -> List Task.FullInstance -> Html Msg
viewTasks env filter tasks =
    let
        isVisible task =
            case filter of
                CompleteTasksOnly ->
                    Task.completed task

                IncompleteTasksOnly ->
                    not (Task.completed task)

                _ ->
                    True

        allCompleted =
            List.all Task.completed tasks
    in
    section
        [ class "main" ]
        [ input
            [ class "toggle-all"
            , type_ "checkbox"
            , name "toggle"
            , Attr.checked allCompleted
            ]
            []
        , label
            [ for "toggle-all" ]
            [ text "Mark all as complete" ]
        , Keyed.ul [ class "task-list" ] <|
            List.map (viewKeyedTask env) (List.filter isVisible tasks)
        ]



-- VIEW INDIVIDUAL ENTRIES


viewKeyedTask : Environment -> Task.FullInstance -> ( String, Html Msg )
viewKeyedTask env task =
    ( String.fromInt task.instance.id, lazy2 viewTask env task )



-- viewTask : Task -> Html Msg


viewTask : Environment -> Task.FullInstance -> Html Msg
viewTask env task =
    li
        [ class "task-entry"
        , classList [ ( "completed", Task.completed task ), ( "editing", False ) ]
        , title <|
            -- hover tooltip
            String.concat
            <|
                List.intersperse "\n" <|
                    List.filterMap identity
                        [ Maybe.map (ID.read >> String.fromInt >> String.append "activity: ") task.class.activity
                        , Just ("importance: " ++ String.fromFloat task.class.importance)
                        ]
        ]
        [ progressSlider task
        , div
            [ class "view", class "slider-overlay" ]
            [ input
                [ class "toggle"
                , type_ "checkbox"
                , Attr.checked (Task.completed task)
                , onClick
                    (if not (Task.completed task) then
                        UpdateProgress task (unitMax task.class.completionUnits)

                     else
                        NoOp
                    )
                ]
                []
            , div [ class "title-and-details" ]
                [ label
                    [ onDoubleClick (EditingTitle task.instance.id True)
                    , onClick (FocusSlider task.instance.id True)
                    , css [ fontWeight (Css.int <| Basics.round (task.class.importance * 200 + 200)), pointerEvents none ]
                    , class "task-title"
                    ]
                    [ text task.class.title ]
                , timingInfo env task
                ]
            , div [ class "sessions" ]
                [ text "No plan" ]
            , button
                [ class "destroy"
                , onClick (Delete task.instance.id)
                ]
                [ text "×" ]
            ]
        , input
            [ class "edit"
            , value task.class.title
            , name "title"
            , id ("task-" ++ String.fromInt task.instance.id)
            , onInput (UpdateTitle task.instance.id)
            , onBlur (EditingTitle task.instance.id False)
            , onEnter (EditingTitle task.instance.id False)
            ]
            []

        --, div [ class "task-drawer", class "slider-overlay" , Attr.hidden False ]
        --    [ label [ for "readyDate" ] [ text "Ready" ]
        --    , input [ type_ "date", name "readyDate", onInput (extractDate task.instance.id "Ready"), pattern "[0-9]{4}-[0-9]{2}-[0-9]{2}" ] []
        --    , label [ for "startDate" ] [ text "Start" ]
        --    , input [ type_ "date", name "startDate", onInput (extractDate task.instance.id "Start"), pattern "[0-9]{4}-[0-9]{2}-[0-9]{2}" ] []
        --    , label [ for "finishDate" ] [ text "Finish" ]
        --    , input [ type_ "date", name "finishDate", onInput (extractDate task.instance.id "Finish"), pattern "[0-9]{4}-[0-9]{2}-[0-9]{2}" ] []
        --    , label [ for "deadlineDate" ] [ text "Deadline" ]
        --    , input [ type_ "date", name "deadlineDate", onInput (extractDate task.instance.id "Deadline"), pattern "[0-9]{4}-[0-9]{2}-[0-9]{2}" ] []
        --    , label [ for "expiresDate" ] [ text "Expires" ]
        --    , input [ type_ "date", name "expiresDate", onInput (extractDate task.instance.id "Expires"), pattern "[0-9]{4}-[0-9]{2}-[0-9]{2}" ] []
        --    ]
        ]


{-| This slider is an html input type=range so it does most of the work for us. (It's accessible, works with arrow keys, etc.) No need to make our own ad-hoc solution! We theme it to look less like a form control, and become the background of our Task entry.
-}
progressSlider : Task.FullInstance -> Html Msg
progressSlider task =
    let
        completion =
            Task.instanceProgress task
    in
    input
        [ class "task-progress"
        , type_ "range"
        , value <| String.fromInt <| getPortion completion
        , Attr.min "0"
        , Attr.max <| String.fromInt <| getWhole completion
        , step
            (if isDiscrete <| getUnits completion then
                "1"

             else
                "any"
            )
        , onInput (extractSliderInput task)
        , onDoubleClick (EditingTitle task.instance.id True)
        , onFocus (FocusSlider task.instance.id True)
        , onBlur (FocusSlider task.instance.id False)
        , dynamicSliderThumbCss (getNormalizedPortion (Task.instanceProgress task))
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


extractSliderInput : Task.FullInstance -> String -> Msg
extractSliderInput task input =
    UpdateProgress task <|
        Basics.round <|
            -- TODO not ideal. keep decimals?
            Maybe.withDefault 0
            <|
                String.toFloat input


{-| Human-friendly text in a task summarizing the various TaskMoments (e.g. the due date)
TODO currently only captures deadline
TODO doesn't specify "ago", "in", etc.
-}
timingInfo : Environment -> Task.FullInstance -> Html Msg
timingInfo env task =
    let
        effortDescription =
            describeEffort task

        uniquePrefix =
            "task-" ++ String.fromInt task.instance.id ++ "-"

        dateLabelNameAndID : String
        dateLabelNameAndID =
            uniquePrefix ++ "due-date-field"

        dueDate_editable =
            editableDateLabel env
                dateLabelNameAndID
                (Maybe.map (HumanMoment.dateFromFuzzy env.timeZone) task.instance.externalDeadline)
                (attemptDateChange env task.instance.id task.instance.externalDeadline "Due")

        timeLabelNameAndID =
            uniquePrefix ++ "due-time-field"

        dueTime_editable =
            editableTimeLabel env
                timeLabelNameAndID
                deadlineTime
                (attemptTimeChange env task.instance.id task.instance.externalDeadline "Due")

        deadlineTime =
            case Maybe.map (HumanMoment.timeFromFuzzy env.timeZone) task.instance.externalDeadline of
                Just (Just timeOfDay) ->
                    Just timeOfDay

                _ ->
                    Nothing
    in
    div
        [ class "timing-info" ]
        ([ text effortDescription ] ++ dueDate_editable ++ dueTime_editable)


editableDateLabel : Environment -> String -> Maybe CalendarDate -> (String -> msg) -> List (Html msg)
editableDateLabel env uniqueName givenDateMaybe changeEvent =
    let
        dateRelativeDescription =
            Maybe.withDefault "whenever" <|
                Maybe.map (Calendar.describeVsToday (HumanMoment.extractDate env.timeZone env.time)) givenDateMaybe

        dateFormValue =
            Maybe.withDefault "" <|
                Maybe.map Calendar.toStandardString givenDateMaybe
    in
    [ label [ for uniqueName, css [ hover [ textDecoration underline ] ] ]
        [ input
            [ type_ "date"
            , name uniqueName
            , id uniqueName
            , css
                [ Css.zIndex (Css.int -1)
                , Css.height (Css.em 1)
                , Css.width (Css.em 2)
                , Css.marginRight (Css.em -2)
                , visibility Css.hidden
                ]
            , onInput changeEvent -- TODO use onchange instead
            , pattern "[0-9]{4}-[0-9]{2}-[0-9]{2}"
            , value dateFormValue
            ]
            []
        , text dateRelativeDescription
        ]
    ]


editableTimeLabel : Environment -> String -> Maybe TimeOfDay -> (String -> msg) -> List (Html msg)
editableTimeLabel env uniqueName givenTimeMaybe changeEvent =
    let
        timeDescription =
            Maybe.withDefault "(+ add time)" <|
                Maybe.map Clock.toShortString givenTimeMaybe

        timeFormValue =
            Maybe.withDefault "" <|
                Maybe.map Clock.toShortString givenTimeMaybe
    in
    [ label
        [ for uniqueName
        , class "editable-time-label"
        ]
        [ text " at "
        , span [ class "time-placeholder" ] [ text timeDescription ]
        ]
    , input
        [ type_ "time"
        , name uniqueName
        , id uniqueName
        , class "editable-time"
        , onInput changeEvent -- TODO use onchange instead
        , pattern "[0-9]{2}:[0-9]{2}" -- for unsupported browsers
        , value timeFormValue
        ]
        []
    ]


describeEffort : Task.FullInstance -> String
describeEffort task =
    let
        sayEffort amount =
            HumanDuration.breakdownNonzero amount
    in
    case ( sayEffort task.class.minEffort, sayEffort task.class.maxEffort ) of
        ( [], [] ) ->
            ""

        ( [], givenMax ) ->
            "up to " ++ HumanDuration.abbreviatedSpaced givenMax ++ " by "

        ( givenMin, [] ) ->
            "at least " ++ HumanDuration.abbreviatedSpaced givenMin ++ " by "

        ( givenMin, givenMax ) ->
            HumanDuration.abbreviatedSpaced givenMin ++ " - " ++ HumanDuration.abbreviatedSpaced givenMax ++ " by "


describeTaskMoment : Moment -> Zone -> FuzzyMoment -> String
describeTaskMoment now zone dueMoment =
    HumanMoment.fuzzyDescription now zone dueMoment


{-| Get the date out of a date input.
-}
attemptDateChange : Environment -> Task.ClassID -> Maybe FuzzyMoment -> String -> String -> Msg
attemptDateChange env task oldFuzzyMaybe field input =
    case Calendar.fromNumberString input of
        Ok newDate ->
            case oldFuzzyMaybe of
                Nothing ->
                    UpdateTaskDate task field (Just (DateOnly newDate))

                Just (DateOnly _) ->
                    UpdateTaskDate task field (Just (DateOnly newDate))

                Just (Floating ( _, oldTime )) ->
                    UpdateTaskDate task field (Just (Floating ( newDate, oldTime )))

                Just (Global oldMoment) ->
                    UpdateTaskDate task field (Just (Global (HumanMoment.setDate newDate env.timeZone oldMoment)))

        Err msg ->
            NoOp


{-| Get the time out of a time input.
TODO Time Zones
-}
attemptTimeChange : Environment -> Task.ClassID -> Maybe FuzzyMoment -> String -> String -> Msg
attemptTimeChange env task oldFuzzyMaybe whichTimeField input =
    case Clock.fromStandardString input of
        Ok newTime ->
            case oldFuzzyMaybe of
                Nothing ->
                    NoOp

                -- can't add a time when there's no date.
                Just (DateOnly oldDate) ->
                    -- we're adding a time!
                    UpdateTaskDate task whichTimeField (Just (Floating ( oldDate, newTime )))

                Just (Floating ( oldDate, _ )) ->
                    UpdateTaskDate task whichTimeField (Just (Floating ( oldDate, newTime )))

                Just (Global oldMoment) ->
                    UpdateTaskDate task whichTimeField (Just (Global (HumanMoment.setTime newTime env.timeZone oldMoment)))

        Err _ ->
            NoOp


viewControls : List Filter -> List Task.FullInstance -> Html Msg
viewControls visibilityFilters tasks =
    let
        tasksCompleted =
            List.length (List.filter Task.completed tasks)

        tasksLeft =
            List.length tasks - tasksCompleted
    in
    footer
        [ class "footer"
        , Attr.hidden (List.isEmpty tasks)
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
        [ visibilitySwap "all" AllTasks visibilityFilters
        , text " "
        , visibilitySwap "active" IncompleteTasksOnly visibilityFilters
        , text " "
        , visibilitySwap "completed" CompleteTasksOnly visibilityFilters
        ]


visibilitySwap : String -> Filter -> List Filter -> Html Msg
visibilitySwap name visibilityToDisplay actualVisibility =
    let
        isCurrent =
            List.member visibilityToDisplay actualVisibility

        changeList =
            if isCurrent then
                List.remove visibilityToDisplay actualVisibility

            else
                visibilityToDisplay :: actualVisibility
    in
    li
        []
        [ input
            [ type_ "checkbox"
            , Attr.checked isCurrent
            , onClick (Refilter changeList)
            , classList [ ( "selected", isCurrent ) ]
            , Attr.name name
            ]
            []
        , label [ for name ] [ text (filterName visibilityToDisplay) ]
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
        , Attr.hidden (tasksCompleted == 0)
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
    = Refilter (List Filter)
    | EditingTitle Task.ClassID Bool
    | UpdateTitle Task.ClassID String
    | Add
    | Delete Task.InstanceID
    | DeleteComplete
    | UpdateProgress Task.FullInstance Portion
    | FocusSlider Task.ClassID Bool
    | UpdateTaskDate Task.ClassID String (Maybe FuzzyMoment)
    | UpdateNewEntryField String
    | NoOp
    | TodoistServerResponse Todoist.Msg


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
                    let
                        newTaskClass =
                            Task.newClass (Task.normalizeTitle newTaskTitle) (Moment.toSmartInt env.time)

                        newTaskInstance =
                            Task.newInstance (Moment.toSmartInt env.time) newTaskClass
                    in
                    ( Normal filters Nothing ""
                      -- resets new-entry-textbox to empty, collapses tasks
                    , { app
                        | taskClasses = IntDict.insert newTaskClass.id newTaskClass app.taskClasses
                        , taskInstances = IntDict.insert newTaskInstance.id newTaskInstance app.taskInstances
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
                    t

                -- TODO editing should be a viewState thing, not a task prop
                focus =
                    Browser.Dom.focus ("task-" ++ String.fromInt id)
            in
            ( state
            , { app | taskInstances = IntDict.update id (Maybe.map updateTask) app.taskInstances }
            , Job.attempt (\_ -> NoOp) focus
            )

        UpdateTitle classID task ->
            let
                updateTitle t =
                    { t | title = task }
            in
            ( state
            , { app | taskClasses = IntDict.update classID (Maybe.map updateTitle) app.taskClasses }
            , Cmd.none
            )

        UpdateTaskDate id field date ->
            let
                updateTask t =
                    { t | externalDeadline = date }
            in
            ( state
            , { app | taskInstances = IntDict.update id (Maybe.map updateTask) app.taskInstances }
            , Cmd.none
            )

        Delete id ->
            ( state
            , { app | taskInstances = IntDict.remove id app.taskInstances }
            , Cmd.none
            )

        DeleteComplete ->
            ( state
            , app
              -- TODO { app | taskInstances = IntDict.filter (\_ t -> not (Task.completed t)) app.taskInstances }
            , Cmd.none
            )

        UpdateProgress givenTask new_completion ->
            let
                updateTask t =
                    { t | completion = new_completion }

                oldProgress =
                    Task.instanceProgress givenTask

                handleCompletion =
                    -- how does the new completion status compare to the previous?
                    case ( isMax oldProgress, isMax ( new_completion, getUnits oldProgress ) ) of
                        ( False, True ) ->
                            -- It was incomplete before, completed now
                            Cmd.batch
                                [ Commands.toast ("Marked as complete: " ++ givenTask.class.title)
                                , Cmd.map TodoistServerResponse <|
                                    Integrations.Todoist.sendChanges app.todoist
                                        [ ( HumanMoment.toStandardString env.time, TodoistCommand.ItemClose (TodoistCommand.RealItem givenTask.instance.id) ) ]
                                ]

                        ( True, False ) ->
                            -- It was complete before, but now marked incomplete
                            Cmd.batch
                                [ Commands.toast ("No longer marked as complete: " ++ givenTask.class.title)
                                , Cmd.map TodoistServerResponse <|
                                    Integrations.Todoist.sendChanges app.todoist
                                        [ ( HumanMoment.toStandardString env.time, TodoistCommand.ItemUncomplete (TodoistCommand.RealItem givenTask.instance.id) ) ]
                                ]

                        _ ->
                            -- nothing changed, completion-wise
                            Cmd.none
            in
            ( state
            , { app
                | taskInstances = IntDict.update givenTask.instance.id (Maybe.map updateTask) app.taskInstances
              }
            , handleCompletion
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

        TodoistServerResponse response ->
            let
                ( newAppData, whatHappened ) =
                    Integrations.Todoist.handle response app
            in
            ( state
            , newAppData
            , Commands.toast whatHappened
            )

        Refilter newList ->
            ( case state of
                Normal filterList expandedTaskMaybe newTaskField ->
                    Normal newList expandedTaskMaybe newTaskField
            , app
            , Cmd.none
            )


urlTriggers : AppData -> Environment -> List ( String, Dict.Dict String Msg )
urlTriggers app env =
    let
        allFullTaskInstances =
            Task.buildFullInstanceDict ( app.taskEntries, app.taskClasses, app.taskInstances )

        tasksPairedWithNames =
            List.map triggerEntry (IntDict.values allFullTaskInstances)

        triggerEntry fullInstance =
            ( fullInstance.class.title, UpdateProgress fullInstance (getWhole (Task.instanceProgress fullInstance)) )

        buildNextTaskEntry nextTaskFullInstance =
            [ ( "next", UpdateProgress nextTaskFullInstance (getWhole (Task.instanceProgress nextTaskFullInstance)) ) ]

        nextTaskEntry =
            Maybe.map buildNextTaskEntry (Activity.Switching.determineNextTask app env)

        noNextTaskEntry =
            [ ( "next", NoOp ) ]

        allEntries =
            Maybe.withDefault noNextTaskEntry nextTaskEntry ++ tasksPairedWithNames
    in
    [ ( "complete", Dict.fromList allEntries )
    ]
