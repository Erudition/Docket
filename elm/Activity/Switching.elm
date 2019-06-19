module Activity.Switching exposing (currentActivityFromApp, sameActivity, switchActivity, switchPopup)

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
    in
    ( updatedApp
    , Cmd.batch
        [ Commands.toast (switchPopup updatedApp.timeline env ( activityID, newActivity ) ( oldActivityID, oldActivity ))
        , Tasker.variableOut ( "ExcusedTotalSec", Measure.exportExcusedUsageSeconds app env.time ( activityID, newActivity ) )
        , Tasker.variableOut ( "OnTaskTotalSec", Measure.exportExcusedUsageSeconds app env.time ( activityID, newActivity ) )
        , Tasker.variableOut ( "ActivityTotal", String.fromInt <| Duration.inMinutesRounded (Measure.excusedUsage app.timeline env.time ( activityID, newActivity )) )
        , Tasker.variableOut ( "ExcusedMaxSec", String.fromInt <| Duration.inSecondsRounded (Measure.excusableLimit newActivity) )
        , Tasker.variableOut ( "ElmSelected", getName newActivity )
        , Tasker.variableOut ( "PreviousSessionTotal", Measure.exportLastSession updatedApp oldActivityID )
        , Commands.hideWindow
        , Commands.scheduleNotify <| scheduleExcusedReminders env.time (HumanDuration.toDuration <| Tuple.second <| Activity.excusableFor newActivity) (Measure.excusedLeft updatedApp.timeline env.time ( activityID, newActivity ))
        ]
    )


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


scheduleReminders : Moment -> Duration -> List Reminder
scheduleReminders now fromNow =
    let
        fractionLeft denom =
            future now <| Duration.subtract fromNow (Duration.scale fromNow (1 / denom))
    in
    [ Reminder (fractionLeft 2)
        "Half-way done!"
        "1/2 time left for activity."
        []
    , Reminder (fractionLeft 3)
        "Two-thirds done!"
        "1/3 time left for activity."
        []
    , Reminder (fractionLeft 4)
        "Three-Quarters done!"
        "1/4 time left for activity."
        []
    , Reminder (future now fromNow)
        "Time's up!"
        "Reached maximum time allowed for this."
        []
    ]
