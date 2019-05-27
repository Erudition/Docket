port module External.ElmjutsuDumMyM0DuL3 exposing (..)
-- exposing (changeActivity, hideWindow, toast)

import Activity.Reminder exposing (..)
import External.Capacitor exposing (..)
import External.Tasker exposing (..)
import Json.Encode as Encode exposing (Value, string)
import Time


scheduleNotify : List Reminder -> Cmd msg
scheduleNotify reminderList =
    notificationsOut (Encode.list encodeNotification reminderList)


encodeNotification : Reminder -> Encode.Value
encodeNotification v =
    let
        encodeNotificationButton button =
            Encode.object
                [ ( "label", Encode.string button.label )
                , ( "action", Encode.string button.action )
                , ( "icon", Encode.string button.icon )
                ]
    in
    Encode.object
        [ ( "title", Encode.string v.title )
        , ( "subtitle", Encode.string v.subtitle )
        , ( "schedule", Encode.int (Time.posixToMillis v.schedule) )
        , ( "actions", Encode.list encodeNotificationButton v.actions )
        ]


toast message =
    flash message


changeActivity newName newTotal =
    Cmd.batch
        [ variableOut ( "ElmSelected", newName )
        , variableOut ( "ActivityTotalSec", newTotal )
        ]


hideWindow =
    exit ()