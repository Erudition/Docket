module Model.Task exposing (..)

import Json.Decode as Decode exposing (..)
import Json.Decode.Pipeline exposing (decode, hardcoded, optional, required)
import Json.Encode as Encode exposing (..)
import Json.Encode.Extra as Encode2 exposing (..)
import Model.Progress exposing (..)
import Model.TaskMoment exposing (..)
import Porting exposing (..)


{-| Definition of a single task.
Working rules:

  - there should be no fields for storing data that can be fully derived from other fields [consistency]
  - combine related fields into a single one with a tuple value [minimalism]

-}
type alias Task =
    { title : String
    , completion : Progress
    , editing : Bool
    , id : TaskId
    , predictedEffort : Duration
    , history : List HistoryEntry
    , parent : Maybe TaskId
    , tags : List String
    , project : Maybe ProjectId
    , deadline : TaskMoment
    , plannedStart : TaskMoment
    , plannedFinish : TaskMoment
    , relevanceStarts : TaskMoment
    , relevanceEnds : TaskMoment
    }


decodeTask : Decode.Decoder Task
decodeTask =
    decode Task
        |> required "title" Decode.string
        |> required "completion" decodeProgress
        |> required "editing" Decode.bool
        |> required "id" Decode.int
        |> required "predictedEffort" Decode.int
        |> required "history" (Decode.list decodeHistoryEntry)
        |> required "parent" (Decode.maybe Decode.int)
        |> required "tags" (Decode.list Decode.string)
        |> required "project" (Decode.maybe Decode.int)
        |> required "deadline" decodeTaskMoment
        |> required "plannedStart" decodeTaskMoment
        |> required "plannedFinish" decodeTaskMoment
        |> required "relevanceStarts" decodeTaskMoment
        |> required "relevanceEnds" decodeTaskMoment


encodeTask : Task -> Encode.Value
encodeTask record =
    Encode.object
        [ ( "title", Encode.string <| record.title )
        , ( "completion", encodeProgress <| record.completion )
        , ( "editing", Encode.bool <| record.editing )
        , ( "id", Encode.int <| record.id )
        , ( "predictedEffort", Encode.int <| record.predictedEffort )
        , ( "history", Encode.list <| List.map encodeHistoryEntry <| record.history )
        , ( "parent", Encode2.maybe Encode.int record.parent )
        , ( "tags", Encode.list <| List.map Encode.string <| record.tags )
        , ( "project", Encode2.maybe Encode.int record.project )
        , ( "deadline", encodeTaskMoment record.deadline )
        , ( "plannedStart", encodeTaskMoment record.plannedStart )
        , ( "plannedFinish", encodeTaskMoment record.plannedFinish )
        , ( "relevanceStarts", encodeTaskMoment record.relevanceStarts )
        , ( "relevanceEnds", encodeTaskMoment record.relevanceEnds )
        ]


newTask : String -> Int -> Task
newTask description id =
    { title = description
    , editing = False
    , id = id
    , completion = ( 0, Percent )
    , parent = Nothing
    , predictedEffort = 0
    , history = []
    , tags = []
    , project = Just 0
    , deadline = Unset
    , plannedStart = Unset
    , plannedFinish = Unset
    , relevanceStarts = Unset
    , relevanceEnds = Unset
    }


{-| Defines a point where something changed in a task.
-}
type alias HistoryEntry =
    ( TaskChange, Moment )


decodeHistoryEntry : Decode.Decoder HistoryEntry
decodeHistoryEntry =
    fail "womp"


encodeHistoryEntry : HistoryEntry -> Encode.Value
encodeHistoryEntry record =
    Encode.object
        []



-- possible ways to filter the list of tasks (legacy)


type TaskListFilter
    = AllTasks
    | ActiveTasksOnly
    | CompletedTasksOnly


{-| possible activities that can be logged about a task.
Working rules:

  - names should just be '(exact name of field being changed)+Change' [consistency]
  - value always includes the full value it was changed to at the time, never the delta [consistency]

-}
type TaskChange
    = Created Moment
    | CompletionChange Progress
    | TitleChange String
    | PredictedEffortChange Duration
    | ParentChange TaskId
    | TagsChange
    | DateChange TaskMoment


decodeTaskChange : Decode.Decoder TaskChange
decodeTaskChange =
    decodeTU "TaskChange"
        [ valueC "CompletionChange" (subValue CompletionChange "progress" decodeProgress)
        , valueC "Created" (subValue Created "moment" decodeMoment)
        , valueC "ParentChange" (subValue ParentChange "taskId" Decode.int)
        , valueC "PredictedEffortChange" (subValue PredictedEffortChange "duration" Decode.int)
        , valueC "TagsChange" (succeed TagsChange)
        , valueC "TitleChange" (subValue TitleChange "string" Decode.string)
        ]


encodeTaskChange : TaskChange -> Encode.Value
encodeTaskChange =
    toString >> Encode.string


type alias TaskId =
    Int


type alias ProjectId =
    Int
