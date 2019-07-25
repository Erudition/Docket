module External.Todoist exposing (Item, Project, TodoistMsg(..), sync)

{-| A library for interacting with the Todoist API.

Allows efficient batch processing and incremental sync.

-}

import Dict exposing (Dict)
import External.Todoist.Command exposing (..)
import Http
import ID
import IntDict exposing (IntDict)
import IntDictExtra as IntDict
import Json.Decode.Exploration as Decode exposing (..)
import Json.Decode.Exploration.Pipeline exposing (..)
import Json.Encode as Encode
import Json.Encode.Extra as Encode2
import List.Extra as List
import List.Nonempty exposing (Nonempty)
import Maybe.Extra as Maybe
import Porting exposing (..)
import SmartTime.Human.Moment as HumanMoment
import Url
import Url.Builder


type alias SecretToken =
    String


{-| Sync with Todoist!

This is a `Platform.Cmd`, you'll need to run it from your `update`.

-}
sync : Cache -> SecretToken -> List Resources -> Cmd TodoistMsg
sync cache secret resourceList =
    Http.post
        { url = Url.toString <| syncUrl secret resourceList cache.lastSync
        , body = Http.emptyBody
        , expect = Http.expectJson SyncResponded (toClassic decodeResponse)
        }


{-| A message for you to add to your app's `Msg` type. Comes back when the sync request succeeded or failed.
-}
type TodoistMsg
    = SyncResponded (Result Http.Error Response)


{-| A place to store your local copy of the user's Todoist data.

By keeping this in your model, you can quickly and easily perform efficient incremental synchronization with Todoist's servers by passing it to the `sync` function! Only the (desired) resources changed since the last sync will be updated, and the commands that didn't go through will be kept around so you can retry them.

That said, this is optional. You can handle the fetched resources individually if you want, or even discard

-}
type alias Cache =
    { lastSync : IncrementalSyncToken
    , items : IntDict Item
    , projects : IntDict Item
    , pendingCommands : List Command
    }


emptyCache : Cache
emptyCache =
    { lastSync = IncrementalSyncToken "*"
    , items = IntDict.empty
    , projects = IntDict.empty
    , pendingCommands = []
    }


decodeTodoistCache : Decoder Cache
decodeTodoistCache =
    decode Cache
        |> optional "lastSync" decodeIncrementalSyncToken emptyCache.lastSync
        |> required "items" decodeIntDict decodeItem
        |> required "projects" decodeIntDict decodeProject
        |> required "pendingCommands" Decode.list decodeCommand


encodeTodoistCache : Cache -> Encode.Value
encodeTodoistCache record =
    Encode.object
        [ ( "lastSync", encodeIncrementalSyncToken record.lastSync )
        , ( "parentProjectID", Encode.int record.parentProjectID )
        , ( "activityProjectIDs", Porting.encodeIntDict ID.encode record.activityProjectIDs )
        ]



-- syncUrl : IncrementalSyncToken  -> Url.Url
-- syncUrl (IncrementalSyncToken incrementalSyncToken) =
--     let
--         allResources =
--             """[%22all%22]"""
--
--         someResources =
--             """[%22items%22,%22projects%22]"""
--
--         devSecret =
--             "0bdc5149510737ab941485bace8135c60e2d812b"
--
--         query =
--             String.concat <|
--                 List.intersperse "&" <|
--                     [ "token=" ++ devSecret
--                     , "sync_token=" ++ incrementalSyncToken
--                     , "resource_types=" ++ someResources
--                     ]
--     in
--     { protocol = Url.Https
--     , host = "todoist.com"
--     , port_ = Nothing
--     , path = "/api/v8/sync"
--     , query = Just query
--     , fragment = Nothing
--     }


syncUrl : SecretToken -> List Resources -> IncrementalSyncToken -> Url.Url
syncUrl secret resourceList (IncrementalSyncToken incrementalSyncToken) =
    let
        chosenResources =
            """[%22items%22,%22projects%22]"""

        resources =
            Encode.list encodeResources resourceList
    in
    Url.Builder.crossOrigin "https://todoist.com"
        [ "api", "v8", "sync" ]
        [ Url.Builder.string "token" secret
        , Url.Builder.string "sync_token" incrementalSyncToken
        , Url.Builder.string "resource_type" (Encode.encode 0 resources)
        ]



-- Fails due to percent-encoding of last field:
-- curl https://todoist.com/api/v8/sync \
--     -d token=0bdc5149510737ab941485bace8135c60e2d812b \
--     -d sync_token='*' \
--     -d resource_types='["all"]'


old_sync : IncrementalSyncToken -> Cmd TodoistMsg
old_sync (IncrementalSyncToken incrementalSyncToken) =
    Http.get
        { url = Url.toString <| syncUrl incrementalSyncToken
        , expect = Http.expectJson SyncResponded (toClassic decodeResponse)
        }


new_syncUrl : IncrementalSyncToken -> List Command -> Url.Url
new_syncUrl (IncrementalSyncToken incrementalSyncToken) commandList =
    let
        commands =
            Encode.list identity commandList

        devSecret =
            "0bdc5149510737ab941485bace8135c60e2d812b"

        query =
            String.concat <|
                List.intersperse "&" <|
                    [ "token=" ++ devSecret
                    , "commands=" ++ Encode.encode 0 commands
                    ]
    in
    { protocol = Url.Https
    , host = "todoist.com"
    , port_ = Nothing
    , path = "/api/v8/sync"
    , query = Just query
    , fragment = Nothing
    }


sendCommands : IncrementalSyncToken -> Cmd TodoistMsg
sendCommands (IncrementalSyncToken incrementalSyncToken) =
    Http.post
        { url = Url.toString <| syncUrl incrementalSyncToken
        , body = Http.emptyBody
        , expect = Http.expectJson SyncResponded (toClassic decodeResponse)
        }


{-| The resources you want to acquire. This is limited to the resources supported by this library, since there's no point in fetching resources and not doing anything with them. Note that currently this intentionally excudes resources that are only relevant to Todoist Premium users (e.g. `labels`, `filters`, `notes`).

(According to the API docs, the full list of supported resource types is: `labels`, `projects`, `items`, `notes`, `filters`, `reminders`, `locations`, `user`, `live_notifications`, `collaborators`, `user_settings`, `notification_settings`. However, there seems to be more (undocumented) types than that, as can be seen when syncing with "all".)

-}
type Resources
    = Projects
    | Items
    | User


encodeResources : Resources -> Encode.Value
encodeResources resource =
    case resource of
        Projects ->
            Encode.string "projects"

        Items ->
            Encode.string "items"

        User ->
            Encode.string "user"


{-| A type that identifies the last successful sync for you, so that you only get resources that have changed since then ("Incremental" sync).

Only the Todoist response can create these values. If you don't have one, you'll have to do a `FullSync` instead (such as on the first sync).

If you get one of these, keep it! You'll use it on your next sync. Discard any older values - if you use an old value, you'll get old changes that you already knew about.

-}
type IncrementalSyncToken
    = IncrementalSyncToken String


decodeIncrementalSyncToken : Decoder IncrementalSyncToken
decodeIncrementalSyncToken =
    Decode.map IncrementalSyncToken Decode.string


encodeIncrementalSyncToken : IncrementalSyncToken -> Encode.Value
encodeIncrementalSyncToken (IncrementalSyncToken token) =
    Encode.string token



-------------------------------- ACTUAL TODOIST STUFF ----------------------NOTE


type alias ItemID =
    Int


type alias UserID =
    Int


type alias ISODateString =
    String


type alias DayOrders =
    Dict ItemID Int


type alias BoolFromInt =
    Int


decodeBoolFromInt : Decoder Bool
decodeBoolFromInt =
    oneOf
        [ check int 1 <| succeed True
        , check int 0 <| succeed False
        ]


encodeBoolAsInt : Bool -> Encode.Value
encodeBoolAsInt bool =
    case bool of
        True ->
            Encode.int 1

        False ->
            Encode.int 0


type alias Item =
    { id : ItemID
    , user_id : UserID
    , project_id : Int
    , content : String
    , due : Maybe Due
    , indent : Int
    , priority : Priority
    , parent_id : Maybe ItemID
    , child_order : Int
    , day_order : Int
    , collapsed : Bool
    , children : List ItemID
    , labels : List LabelID
    , assigned_by_uid : UserID
    , responsible_uid : Maybe UserID
    , checked : Bool
    , in_history : Bool
    , is_deleted : Bool
    , is_archived : Bool
    , date_added : ISODateString
    }


decodeItem : Decoder Item
decodeItem =
    decode Item
        |> required "id" int
        |> required "user_id" int
        |> required "project_id" int
        |> required "content" string
        |> required "due" (nullable decodeDue)
        |> optional "indent" int 0
        |> required "priority" decodePriority
        |> required "parent_id" (nullable int)
        |> required "child_order" int
        -- API docs has incorrect "item_order" in example code (only)
        |> required "day_order" int
        |> required "collapsed" decodeBoolAsInt
        |> optional "children" (list int) []
        |> required "labels" (list int)
        |> optional "assigned_by_uid" int 0
        |> required "responsible_uid" (nullable int)
        |> required "checked" decodeBoolAsInt
        |> required "in_history" decodeBoolAsInt
        |> required "is_deleted" decodeBoolAsInt
        |> optional "is_archived" decodeBoolAsInt False
        -- API docs do not indicate this is an optional field
        |> required "date_added" string
        |> optionalIgnored "legacy_id"
        |> optionalIgnored "legacy_project_id"
        |> optionalIgnored "legacy_parent_id"
        |> optionalIgnored "sync_id"
        |> optionalIgnored "date_completed"
        |> optionalIgnored "has_more_notes"
        |> optionalIgnored "section_id"
        -- only shows up during deletions?
        |> optionalIgnored "due_is_recurring"


encodeItem : Item -> Encode.Value
encodeItem record =
    Encode.object
        [ ( "id", Encode.int <| record.id )
        , ( "user_id", Encode.int <| record.user_id )
        , ( "project_id", Encode.int <| record.project_id )
        , ( "content", Encode.string <| record.content )
        , ( "due", Encode2.maybe encodeDue <| record.due )
        , ( "indent", Encode.int <| record.indent )
        , ( "priority", encodePriority <| record.priority )
        , ( "parent_id", Encode2.maybe Encode.int <| record.parent_id )
        , ( "child_order", Encode.int <| record.child_order )
        , ( "day_order", Encode.int <| record.day_order )
        , ( "collapsed", encodeBoolAsInt <| record.collapsed )
        , ( "children", Encode.list Encode.int <| record.children )
        , ( "labels", Encode.list Encode.int <| record.labels )
        , ( "assigned_by_uid", Encode.int <| record.assigned_by_uid )
        , ( "responsible_uid", Encode2.maybe Encode.int <| record.responsible_uid )
        , ( "checked", encodeBoolAsInt <| record.checked )
        , ( "in_history", encodeBoolAsInt <| record.in_history )
        , ( "is_deleted", encodeBoolAsInt <| record.is_deleted )
        , ( "is_archived", encodeBoolAsInt <| record.is_archived )
        , ( "date_added", Encode.string <| record.date_added )
        ]


type Priority
    = Priority Int


decodePriority : Decoder Priority
decodePriority =
    oneOf
        [ check int 4 <| succeed (Priority 1)
        , check int 3 <| succeed (Priority 2)
        , check int 2 <| succeed (Priority 3)
        , check int 1 <| succeed (Priority 4)
        ]


encodePriority : Priority -> Encode.Value
encodePriority priority =
    case priority of
        Priority 1 ->
            Encode.int 4

        Priority 2 ->
            Encode.int 3

        Priority 3 ->
            Encode.int 2

        _ ->
            Encode.int 1


{-| A Todoist "project", represented exactly the way the API describes it.
-}
type alias Project =
    { id : RealProjectID
    , name : String
    , color : Int
    , parent_id : Maybe Int
    , child_order : Int
    , collapsed : Int
    , shared : Bool
    , is_deleted : BoolFromInt
    , is_archived : BoolFromInt
    , is_favorite : BoolFromInt
    , inbox_project : Bool
    , team_inbox : Bool
    }



-- {-| Needed?
--
-- -}
-- newProject : String -> Int -> Project
-- newProject newName =
--     { id =
--     , name = ""
--     , color = 0
--     , parentId = 0
--     , childOrder = 0
--     , collapsed = 0
--     , shared = False
--     , is_deleted = 0
--     , is_archived = 0
--     , is_favorite = 0
--     }


decodeProject : Decoder Project
decodeProject =
    decode Project
        |> required "id" int
        |> required "name" string
        |> required "color" int
        |> required "parent_id" (nullable int)
        |> required "child_order" int
        |> required "collapsed" int
        |> required "shared" bool
        |> required "is_deleted" decodeBoolFromInt
        |> required "is_archived" decodeBoolFromInt
        |> required "is_favorite" decodeBoolFromInt
        |> optional "inbox_project" bool False
        |> optional "team_inbox" bool False
        |> optionalIgnored "legacy_parent_id"
        |> optionalIgnored "legacy_id"
        |> optionalIgnored "has_more_notes"



--should be id 1 anyway


encodeProject : Project -> Encode.Value
encodeProject record =
    Encode.object
        [ ( "id", Encode.int <| record.id )
        , ( "name", Encode.string <| record.name )
        , ( "color", Encode.int <| record.color )
        , ( "parent_id", Encode2.maybe Encode.int <| record.parentId )
        , ( "child_order", Encode.int <| record.childOrder )
        , ( "collapsed", Encode.int <| record.collapsed )
        , ( "shared", Encode.bool <| record.shared )
        , ( "is_deleted", encodeBoolAsInt <| record.isDeleted )
        , ( "is_archived", encodeBoolAsInt <| record.isArchived )
        , ( "is_favorite", encodeBoolAsInt <| record.isFavorite )
        , ( "inbox_project", Encode.bool <| record.inbox_project )
        , ( "team_inbox", Encode.bool <| record.team_inbox )
        ]


type alias Due =
    { date : String
    , timezone : Maybe String
    , string : String
    , lang : String
    , isRecurring : Bool
    }


decodeDue : Decoder Due
decodeDue =
    decode Due
        |> required "date" string
        |> required "timezone" (nullable string)
        |> required "string" string
        |> required "lang" string
        |> required "is_recurring" bool


encodeDue : Due -> Encode.Value
encodeDue record =
    Encode.object
        [ ( "date", string <| record.date )
        , ( "timezone", Encode2.maybe Encode.string <| record.timezone )
        , ( "string", Encode.string <| record.string )
        , ( "lang", Encode.string <| record.lang )
        , ( "is_recurring", Encode.bool <| record.isRecurring )
        ]


fromRFC3339Date : String -> Maybe HumanMoment.FuzzyMoment
fromRFC3339Date =
    Result.toMaybe << HumanMoment.fuzzyFromString


toRFC3339Date : HumanMoment.FuzzyMoment -> String
toRFC3339Date dateString =
    HumanMoment.fuzzyToString dateString



--------------------------------- RESPONSE ---------------------------------NOTE


handleResponse : TodoistMsg -> Cache -> Result Http.Error Cache
handleResponse (SyncResponded response) oldCache =
    case response of
        Ok new ->
            let
                -- creates a dictionary out of the returned projects
                projectsDict =
                    IntDict.fromList (List.map (\p -> ( p.id, p )) new.projects)

                itemsDict =
                    IntDict.fromList (List.map (\i -> ( i.id, i )) new.items)

                -- Only remove deleted if it's a partial sync. We won't get deleted items on a full sync anyway, and that would take the longest to map over.
                prune inputDict =
                    if not new.full_sync then
                        pruneDeleted inputDict

                    else
                        inputDict
            in
            Ok
                { lastSync = Maybe.withDefault oldCache.lastSync new.sync_token
                , items = prune <| IntDict.union itemsDict oldCache.items
                , projects = prune <| IntDict.union projectsDict oldCache.projects
                }

        Err err ->
            err


{-| An example of how you can handle the output of `handleResponse`. Wraps it.
-}
smartHandle : TodoistMsg -> Cache -> ( Cache, String )
smartHandle inputMsg oldCache =
    let
        runHandler =
            handleResponse inputMsg oldCache

        handleError description =
            ( oldCache, description )
    in
    case runHandler of
        Ok newCache ->
            ( newCache, "Success" )

        Err error ->
            case error of
                Http.BadUrl msg ->
                    handleError <| "For some reason we were told the URL is bad. This should never happen, it's a perfectly tested working URL! The error: " ++ msg

                Http.Timeout ->
                    handleError "Timed out. Try again later?"

                Http.NetworkError ->
                    handleError "Network Error. That's all we know."

                Http.BadStatus status ->
                    -- TODO handle Todoist codes
                    handleError <| "Got HTTP Error code " ++ String.fromInt status

                Http.BadBody string ->
                    handleError <| "Response says the body was bad. That's weird, because we don't send any body to Todoist servers, and the API doesn't ask you to. Here's the error: " ++ string


pruneDeleted : IntDict { a | is_deleted : Bool } -> IntDict { a | is_deleted : Bool }
pruneDeleted items =
    IntDict.filterValues (not << .is_deleted) items


type alias Response =
    { sync_token : Maybe IncrementalSyncToken
    , sync_status : Dict CommandUUID CommandResult
    , full_sync : Bool
    , items : List Item
    , projects : List Project
    }


decodeResponse : Decoder Response
decodeResponse =
    decode Response
        |> optional "sync_token" (Decode.map Just decodeIncrementalSyncToken) Nothing
        |> optional "sync_status" (Decode.dict decodeCommandResult) Dict.empty
        |> required "full_sync" bool
        |> optional "items" (list decodeItem) []
        |> optional "projects" (list decodeProject) []
        |> optionalIgnored "collaborators"
        |> optionalIgnored "collaborator_states"
        |> optionalIgnored "day_orders"
        |> optionalIgnored "filters"
        |> optionalIgnored "labels"
        |> optionalIgnored "live_notifications"
        |> optionalIgnored "live_notifications_last_read_id"
        |> optionalIgnored "notes"
        |> optionalIgnored "project_notes"
        |> optionalIgnored "reminders"
        |> optionalIgnored "settings_notifications"
        |> optionalIgnored "temp_id_mapping"
        |> optionalIgnored "user"
        |> optionalIgnored "user_settings"
        |> optionalIgnored "sections"
        -- each item below not in spec!
        |> optionalIgnored "due_exceptions"
        |> optionalIgnored "day_orders_timestamp"
        |> optionalIgnored "incomplete_project_ids"
        |> optionalIgnored "incomplete_item_ids"
        |> optionalIgnored "stats"
        |> optionalIgnored "locations"
        |> optionalIgnored "tooltips"
