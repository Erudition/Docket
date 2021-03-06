port module External.Tasker exposing (exit, flash, variableOut)

import Json.Encode exposing (Value)


port flash : String -> Cmd msg


port exit : () -> Cmd msg


port variableOut : ( String, String ) -> Cmd msg
