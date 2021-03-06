port module NativeScript.Commands exposing (notify, notifyCancel)

import Json.Encode as Encode exposing (Value, string)
import NativeScript.Notification as Notification


notify : List Notification.Notification -> Cmd msg
notify notification =
    ns_notify (Encode.list Notification.encode notification)


notifyCancel : Notification.NotificationID -> Cmd msg
notifyCancel id =
    ns_notify_cancel (Encode.int id)


port ns_notify : Encode.Value -> Cmd msg


port ns_notify_cancel : Encode.Value -> Cmd msg


port ns_toast : Encode.Value -> Cmd msg
