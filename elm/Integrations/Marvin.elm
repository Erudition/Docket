module Integrations.Marvin exposing (..)

{-| A library for interacting with the Amazing Marvin API.
-}

import Dict exposing (Dict)
import Http
import IntDict exposing (IntDict)
import Integrations.Marvin.MarvinItem exposing (MarvinItem, toDocketTaskNaive)
import Json.Decode.Exploration as Decode exposing (..)
import Json.Decode.Exploration.Pipeline exposing (..)
import Json.Encode as Encode
import Json.Encode.Extra as Encode
import List.Extra as List
import List.Nonempty exposing (Nonempty)
import Maybe.Extra as Maybe
import Porting exposing (..)
import Set exposing (Set)
import SmartTime.Human.Moment as HumanMoment
import Task.Class
import Task.Entry
import Task.Instance
import Url
import Url.Builder


type alias SecretToken =
    String


type alias SecretFullToken =
    String


marvinEndpointURL : String -> String
marvinEndpointURL endpoint =
    Url.Builder.crossOrigin "https://serv.amazingmarvin.com"
        [ "api", endpoint ]
        []


marvinDocURL : String -> String
marvinDocURL docID =
    Url.Builder.crossOrigin "https://serv.amazingmarvin.com"
        [ "api", "doc" ]
        [ Url.Builder.string "id" docID ]


test : SecretToken -> Cmd Msg
test secret =
    Http.request
        { method = "POST"
        , headers = [ Http.header "X-API-Token" secret ]
        , url = marvinEndpointURL "test"
        , body = Http.emptyBody
        , expect = Http.expectString TestResult
        , timeout = Nothing
        , tracker = Nothing
        }


test2 : Cmd Msg
test2 =
    let
        fullAccessToken =
            "7o0b6/c0i+zXgWx5eheuM7Eob7w="

        partialAccessToken =
            "m47dqHEwdJy56/j8tyAcXARlADg="
    in
    getTodayItems partialAccessToken


handle : Int -> Msg -> ( { taskEntries : List Task.Entry.Entry, taskClasses : IntDict Task.Class.ClassSkel, taskInstances : IntDict Task.Instance.InstanceSkel }, String )
handle classCounter response =
    case response of
        TestResult result ->
            case result of
                Ok serversays ->
                    ( { taskEntries = [], taskClasses = IntDict.empty, taskInstances = IntDict.empty }
                    , serversays
                    )

                Err err ->
                    ( { taskEntries = [], taskClasses = IntDict.empty, taskInstances = IntDict.empty }
                    , describeError err
                    )

        GotItems result ->
            case result of
                Ok itemList ->
                    ( importItems classCounter itemList
                    , Debug.toString itemList
                    )

                Err err ->
                    ( { taskEntries = [], taskClasses = IntDict.empty, taskInstances = IntDict.empty }
                    , describeError err
                    )


importItems : Int -> List MarvinItem -> { taskEntries : List Task.Entry.Entry, taskClasses : IntDict Task.Class.ClassSkel, taskInstances : IntDict Task.Instance.InstanceSkel }
importItems classCounter itemList =
    let
        toNumberedDocketTask index =
            toDocketTaskNaive (classCounter + index)

        bigList =
            List.indexedMap toNumberedDocketTask itemList
    in
    { taskEntries = List.map .entry bigList
    , taskClasses = IntDict.fromList <| List.map (\i -> ( i.class.id, i.class )) bigList
    , taskInstances = IntDict.fromList <| List.map (\i -> ( i.instance.id, i.instance )) bigList
    }


addTask : SecretToken -> Cmd Msg
addTask secret =
    Http.request
        { method = "POST"
        , headers = [ Http.header "X-API-Token" secret ]
        , url = marvinEndpointURL "addTask"
        , body = Http.emptyBody -- TODO task
        , expect = Http.expectString TestResult
        , timeout = Nothing
        , tracker = Nothing
        }


addProject : SecretToken -> Cmd Msg
addProject secret =
    Http.request
        { method = "POST"
        , headers = [ Http.header "X-API-Token" secret ]
        , url = marvinEndpointURL "addProject"
        , body = Http.emptyBody -- TODO project
        , expect = Http.expectString TestResult
        , timeout = Nothing
        , tracker = Nothing
        }


type alias Document =
    String


getDoc : SecretFullToken -> Document -> Cmd Msg
getDoc fullSecret doc =
    Http.request
        { method = "GET"
        , headers = [ Http.header "X-Full-Access-Token" fullSecret ]
        , url = marvinDocURL doc
        , body = Http.emptyBody -- TODO project
        , expect = Http.expectString TestResult
        , timeout = Nothing
        , tracker = Nothing
        }


getTrackedItem : SecretToken -> Cmd Msg
getTrackedItem secret =
    Http.request
        { method = "GET"
        , headers = [ Http.header "X-API-Token" secret ]
        , url = marvinEndpointURL "trackedItem"
        , body = Http.emptyBody
        , expect = Http.expectString TestResult
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Get tasks and projects scheduled today (including rollover/auto-schedule due items if enabled)
-}
getTodayItems : SecretToken -> Cmd Msg
getTodayItems secret =
    Http.request
        { method = "GET"
        , headers = [ Http.header "X-API-Token" secret ]
        , url = marvinEndpointURL "todayItems"
        , body = Http.emptyBody
        , expect = Http.expectJson GotItems (toClassic <| Decode.list Integrations.Marvin.MarvinItem.decodeMarvinItem)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Get tasks and projects that are due today
-}
getDueItems : SecretToken -> Cmd Msg
getDueItems secret =
    Http.request
        { method = "GET"
        , headers = [ Http.header "X-API-Token" secret ]
        , url = marvinEndpointURL "dueItems"
        , body = Http.emptyBody
        , expect = Http.expectString TestResult --TODO
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Get a list of all categories
-}
getCategories : SecretToken -> Cmd Msg
getCategories secret =
    Http.request
        { method = "GET"
        , headers = [ Http.header "X-API-Token" secret ]
        , url = marvinEndpointURL "categories"
        , body = Http.emptyBody
        , expect = Http.expectString TestResult --TODO
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Get a list of all labels
-}
getLabels : SecretToken -> Cmd Msg
getLabels secret =
    Http.request
        { method = "GET"
        , headers = [ Http.header "X-API-Token" secret ]
        , url = marvinEndpointURL "labels"
        , body = Http.emptyBody
        , expect = Http.expectString TestResult --TODO
        , timeout = Nothing
        , tracker = Nothing
        }


{-| start or stop time tracking a task by its ID
-}
timeTrack : SecretToken -> String -> Cmd Msg
timeTrack secret taskID =
    Http.request
        { method = "POST"
        , headers = [ Http.header "X-API-Token" secret ]
        , url = marvinEndpointURL "time"
        , body =
            Http.jsonBody <|
                Encode.object
                    [ ( "taskId", Encode.string taskID ), ( "action", Encode.string "START" ) ]
        , expect = Http.expectString TestResult --TODO
        , timeout = Nothing
        , tracker = Nothing
        }


{-| A message for you to add to your app's `Msg` type. Comes back when the sync request succeeded or failed.
-}
type Msg
    = TestResult (Result Http.Error String)
    | GotItems (Result Http.Error (List Integrations.Marvin.MarvinItem.MarvinItem))



--| SyncResponded (Result Http.Error Response)
--------------------------------- RESPONSE ---------------------------------NOTE


describeError : Http.Error -> String
describeError error =
    case error of
        Http.BadUrl msg ->
            "For some reason we were told the URL is bad. This should never happen, it's a perfectly tested working URL! The error: " ++ msg

        Http.Timeout ->
            "Timed out. Try again later?"

        Http.NetworkError ->
            "Are you offline? I couldn't get on the network, but it could also be your system blocking me."

        Http.BadStatus status ->
            case status of
                400 ->
                    "400 Bad Request: The request was incorrect."

                401 ->
                    "401 Unauthorized: Authentication is required, and has failed, or has not yet been provided. Maybe your API credentials are messed up?"

                403 ->
                    "403 Forbidden: The request was valid, but for something that is forbidden."

                404 ->
                    "404 Not Found! That should never happen, because I definitely used the right URL. Is your system or proxy blocking or messing with internet requests? Is it many years in future, where the API has been deprecated, obsoleted, and then discontinued? Or maybe it's far enough in the future that the service doesn't exist anymore but for some reason you're still using this version of the software?"

                429 ->
                    "429 Too Many Requests: Slow down, cowboy! Check out the API Docs for Usage Limits."

                500 ->
                    "500 Internal Server Error: They got the message, and it got confused"

                502 ->
                    "502 Bad Gateway: I was trying to reach the server but I got stopped along the way. If you're definitely connected, it's probably a temporary hiccup on their side -- but if you see this a lot, check that your DNS is resolving (try amazingmarvin.com) and any proxy setup you have is working."

                503 ->
                    "503 Service Unavailable: Not my fault! The service must be bogged down today, or perhaps experiencing a DDoS attack. :O"

                other ->
                    "Got HTTP Error code " ++ String.fromInt other ++ ", not sure what that means in this case. Sorry!"

        Http.BadBody string ->
            "I successfully talked with the servers, but the response had some weird parts I was never trained for. Either Marvin changed something recently, or you've found a weird edge case the developer didn't know about. Either way, please report this! \n" ++ string
