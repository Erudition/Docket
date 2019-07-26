module Incubator.Todoist exposing (Cache, IncrementalSyncToken(..), Resources(..), Response, SecretToken, TodoistMsg(..), decodeCache, decodeIncrementalSyncToken, decodeResponse, emptyCache, encodeCache, encodeIncrementalSyncToken, encodeResources, handleResponse, pruneDeleted, serverUrl, smartHandle, sync)

{-| A library for interacting with the Todoist API.

Allows efficient batch processing and incremental sync.

-}

import Dict exposing (Dict)
import Http
import Incubator.IntDict.Extra as IntDict
import Incubator.Todoist.Command exposing (..)
import Incubator.Todoist.Item as Item exposing (Item)
import Incubator.Todoist.Project as Project exposing (Project)
import IntDict exposing (IntDict)
import Json.Decode.Exploration as Decode exposing (..)
import Json.Decode.Exploration.Pipeline exposing (..)
import Json.Encode as Encode
import Json.Encode.Extra as Encode
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
sync : Cache -> SecretToken -> List Resources -> List Command -> Cmd TodoistMsg
sync cache secret resourceList commandList =
    Http.post
        { url = serverUrl secret resourceList commandList cache.lastSync
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
    , projects : IntDict Project
    , pendingCommands : List String
    }


emptyCache : Cache
emptyCache =
    { lastSync = IncrementalSyncToken "*"
    , items = IntDict.empty
    , projects = IntDict.empty
    , pendingCommands = []
    }


decodeCache : Decoder Cache
decodeCache =
    decode Cache
        |> optional "lastSync" decodeIncrementalSyncToken emptyCache.lastSync
        |> required "items" (decodeIntDict Item.decodeItem)
        |> required "projects" (decodeIntDict Project.decodeProject)
        |> required "pendingCommands" (Decode.list Decode.string)


encodeCache : Cache -> Encode.Value
encodeCache record =
    Encode.object
        [ ( "lastSync", encodeIncrementalSyncToken record.lastSync )
        , ( "items", encodeIntDict Item.encodeItem record.items )
        , ( "projects", encodeIntDict Project.encodeProject record.projects )
        , ( "pendingCommands", Encode.list Encode.string record.pendingCommands )
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


serverUrl : SecretToken -> List Resources -> List Command -> IncrementalSyncToken -> String
serverUrl secret resourceList commandList (IncrementalSyncToken syncToken) =
    let
        chosenResources =
            """[%22items%22,%22projects%22]"""

        resources =
            Encode.list encodeResources resourceList

        commands =
            Encode.list encodeCommand commandList

        withRead =
            if List.length resourceList > 0 then
                [ Url.Builder.string "sync_token" syncToken
                , Url.Builder.string "resource_types" (Encode.encode 0 resources)
                ]

            else
                []

        withWrite =
            if List.length commandList > 0 then
                [ Url.Builder.string "commands" (Encode.encode 0 commands) ]

            else
                []
    in
    Url.Builder.crossOrigin "https://todoist.com"
        [ "api", "v8", "sync" ]
        ([ Url.Builder.string "token" secret ] ++ withRead ++ withWrite)



-- Fails due to percent-encoding of last field:
-- curl https://todoist.com/api/v8/sync \
--     -d token=0bdc5149510737ab941485bace8135c60e2d812b \
--     -d sync_token='*' \
--     -d resource_types='["all"]'
-- old_sync : IncrementalSyncToken -> Cmd TodoistMsg
-- old_sync (IncrementalSyncToken incrementalSyncToken) =
--     Http.get
--         { url = Url.toString <| syncUrl incrementalSyncToken
--         , expect = Http.expectJson SyncResponded (toClassic decodeResponse)
--         }


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
                , pendingCommands = []
                }

        Err err ->
            Result.Err err


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
        |> optional "items" (list Item.decodeItem) []
        |> optional "projects" (list Project.decodeProject) []
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
