module Activity.Switching exposing (currentActivityFromApp, determineNextTask, sameActivity, switchActivity)

import Activity.Activity as Activity exposing (..)
import Activity.Measure as Measure
import Activity.Reminder exposing (..)
import AppData exposing (..)
import Environment exposing (..)
import External.Commands as Commands
import External.Tasker as Tasker
import IntDict
import SmartTime.Duration as Duration exposing (Duration)
import SmartTime.Human.Duration as HumanDuration exposing (..)
import SmartTime.Moment exposing (..)
import Task.Task as Task
import Time
import Time.Extra as Time


switchActivity : ActivityID -> AppData -> Environment -> ( AppData, Cmd msg )
switchActivity activityID app env =
    let
        updatedApp =
            { app | timeline = Switch env.time activityID :: app.timeline }

        newActivity =
            Activity.getActivity activityID (allActivities app.activities)

        oldActivity =
            Activity.getActivity oldActivityID (allActivities app.activities)

        oldActivityID =
            currentActivityFromApp app

        onTaskStatus =
            determineOnTask activityID app env
    in
    ( updatedApp
    , Cmd.batch
        [ Commands.toast (switchPopup updatedApp.timeline env ( activityID, newActivity ) ( oldActivityID, oldActivity ))
        , Tasker.variableOut ( "OnTaskStatus", Activity.statusToString onTaskStatus )
        , Tasker.variableOut ( "ExcusedUsage", Measure.exportExcusedUsageSeconds app env.time ( activityID, newActivity ) )
        , Tasker.variableOut ( "OnTaskUsage", Measure.exportExcusedUsageSeconds app env.time ( activityID, newActivity ) )
        , Tasker.variableOut ( "ActivityTotal", String.fromInt <| Duration.inMinutesRounded (Measure.excusedUsage app.timeline env.time ( activityID, newActivity )) )
        , Tasker.variableOut ( "ExcusedLimit", String.fromInt <| Duration.inSecondsRounded (Measure.excusableLimit newActivity) )
        , Tasker.variableOut ( "CurrentActivity", getName newActivity )
        , Tasker.variableOut ( "PreviousSessionTotal", Measure.exportLastSession updatedApp oldActivityID )
        , Commands.hideWindow
        , Commands.scheduleNotify <| scheduleReminders env updatedApp.timeline onTaskStatus ( activityID, newActivity )
        , exportNextTask app env
        ]
    )


scheduleReminders : Environment -> Timeline -> OnTaskStatus -> ( ActivityID, Activity ) -> List Alarm
scheduleReminders env timeline onTaskStatus ( activityID, newActivity ) =
    case onTaskStatus of
        OnTask timeLeft ->
            scheduleOnTaskReminders env.time timeLeft

        OffTask excusedLeft ->
            --TODO handle indefinitely excused
            if Duration.isPositive excusedLeft then
                scheduleExcusedReminders env.time (Measure.excusableLimit newActivity) excusedLeft

            else
                scheduleOffTaskReminders env.time

        AllDone ->
            []


determineOnTask : ActivityID -> AppData -> Environment -> OnTaskStatus
determineOnTask activityID app env =
    let
        current =
            getActivity activityID (allActivities app.activities)

        excusedLeft =
            Measure.excusedLeft app.timeline env.time ( activityID, current )
    in
    case determineNextTask app env of
        Nothing ->
            AllDone

        Just nextTask ->
            case nextTask.activity of
                Nothing ->
                    OffTask excusedLeft

                Just nextActivity ->
                    if nextActivity == activityID then
                        OnTask nextTask.maxEffort

                    else
                        OffTask excusedLeft


determineNextTask : AppData -> Environment -> Maybe Task.Task
determineNextTask app env =
    List.head <|
        Task.prioritize env.time env.timeZone <|
            List.filter (Task.completed >> not) <|
                IntDict.values app.tasks


exportNextTask : AppData -> Environment -> Cmd msg
exportNextTask app env =
    let
        next =
            determineNextTask app env

        export task =
            Tasker.variableOut ( "NextTaskTitle", task.title )
    in
    Maybe.withDefault Cmd.none (Maybe.map export next)


sameActivity : ActivityID -> AppData -> Environment -> ( AppData, Cmd msg )
sameActivity activityID app env =
    let
        activity =
            Activity.getActivity activityID (allActivities app.activities)
    in
    ( app
    , Cmd.batch
        [ Commands.toast (switchPopup app.timeline env ( activityID, activity ) ( activityID, activity ))
        , Commands.changeActivity
            (getName activity)
            (Measure.exportExcusedUsageSeconds app env.time ( activityID, activity ))
            (String.fromInt <| Duration.inSecondsRounded (Measure.excusableLimit activity))
            (Measure.exportLastSession app activityID)
        , Commands.hideWindow
        ]
    )


switchPopup : Timeline -> Environment -> ( ActivityID, Activity ) -> ( ActivityID, Activity ) -> String
switchPopup timeline env (( newID, new ) as newKV) ( oldID, old ) =
    let
        timeSpentString dur =
            singleLetterSpaced (breakdownMS dur)

        timeSpentLastSession =
            Maybe.withDefault Duration.zero (List.head (Measure.sessions timeline oldID))
    in
    timeSpentString timeSpentLastSession
        ++ " spent on "
        ++ getName old
        ++ "\n"
        ++ getName old
        ++ " ➤ "
        ++ getName new
        ++ "\n"
        ++ "Starting from "
        ++ timeSpentString (Measure.excusedUsage timeline env.time newKV)


currentActivityFromApp : AppData -> ActivityID
currentActivityFromApp app =
    currentActivityID app.timeline
