module Integrations.Todoist exposing (describeSuccess, devSecret, extractTiming, extractTiming2, findActivityProjectIDs, handle, itemToTask, priorityToImportance, timetrackItemToTask, timing)

import Activity.Activity as Activity exposing (Activity, ActivityID)
import AppData exposing (AppData, TodoistIntegrationData, saveError)
import Dict exposing (Dict)
import Http
import ID
import Incubator.IntDict.Extra as IntDict
import Incubator.Todoist as Todoist
import Incubator.Todoist.Item as Item exposing (Item)
import Incubator.Todoist.Project as Project exposing (Project)
import IntDict exposing (IntDict)
import Json.Decode.Exploration as Decode exposing (..)
import Json.Decode.Exploration.Pipeline exposing (..)
import Json.Encode as Encode
import Json.Encode.Extra as Encode2
import List.Extra as List
import List.Nonempty exposing (Nonempty)
import Maybe.Extra as Maybe
import Parser exposing ((|.), (|=), Parser, float, spaces, symbol)
import Porting exposing (..)
import SmartTime.Duration as Duration exposing (Duration)
import SmartTime.Human.Calendar as Calendar exposing (CalendarDate)
import SmartTime.Human.Duration as HumanDuration exposing (HumanDuration)
import SmartTime.Human.Moment as HumanMoment exposing (FuzzyMoment)
import Task.Progress
import Task.Task exposing (Task, newTask)
import Url
import Url.Builder


devSecret : Todoist.SecretToken
devSecret =
    "0bdc5149510737ab941485bace8135c60e2d812b"


handle : Todoist.Msg -> AppData -> ( AppData, String )
handle msg app =
    case Todoist.handleResponse msg app.todoist.cache of
        Ok newCache ->
            let
                updatedTimetrackParent =
                    -- TODO only do once
                    List.head <| IntDict.keys <| IntDict.filter (\_ p -> p.name == "Timetrack") newCache.projects

                timetrackParent =
                    Maybe.withDefault app.todoist.parentProjectID updatedTimetrackParent

                validActivityProjects =
                    IntDict.filter (\_ p -> p.parent_id == timetrackParent) newCache.projects

                newActivityLookupTable =
                    findActivityProjectIDs validActivityProjects filledInActivities

                combinedALT =
                    IntDict.union newActivityLookupTable app.todoist.activityProjectIDs

                itemsInTimetrackToTasks =
                    List.filterMap
                        (timetrackItemToTask combinedALT)
                        newCache.items

                filledInActivities =
                    Activity.allActivities app.activities

                generatedTasks =
                    IntDict.fromList <|
                        Debug.log "generated task list" <|
                            List.map (\t -> ( t.id, t )) <|
                                itemsInTimetrackToTasks
            in
            ( { app
                | todoist =
                    { cache = newCache
                    , parentProjectID = timetrackParent
                    , activityProjectIDs = combinedALT
                    }
                , tasks =
                    -- TODO figure out deleted
                    IntDict.union generatedTasks app.tasks
              }
            , describeSuccess newCache
            )

        Err err ->
            let
                description =
                    Todoist.describeError err
            in
            ( saveError app description, description )


describeSuccess : Todoist.Response -> String
describeSuccess success =
    if success.full_sync then
        "Did FULL Todoist sync: "
            ++ String.fromInt (List.length success.items)
            ++ " items, "
            ++ String.fromInt (List.length success.projects)
            ++ " projects retrieved!"

    else
        "Incremental Todoist sync complete: Updated "
            ++ String.fromInt (List.length success.items)
            ++ " items and "
            ++ String.fromInt (List.length success.projects)
            ++ "projects."


{-| Take our todoist-project dictionary and our activity dictionary, and create a translation table between them.
-}
findActivityProjectIDs : IntDict Project -> IntDict Activity -> IntDict ActivityID
findActivityProjectIDs projects activities =
    -- phew! this was a hard one conceptually :) Looks clean though!
    let
        -- The only part of our activities we care about here is the name field, so we reduce the activities to just their name list
        activityNamesDict =
            IntDict.mapValues .names activities

        -- Our IntDict's (Keys, Values) are (activityID, nameList). This function gets mapped to our dictionary to check for matches. what was once a dictionary of names is now a dictionary of Maybe ActivityIDs.
        matchToID nameToTest activityID nameList =
            if List.member nameToTest nameList then
                -- Wrap values we want to keep
                Just (ID.tag activityID)

            else
                -- No match, will be removed from the dict
                Nothing

        -- Try a given name with matchToID, filter out the nothings, which should either be all of them, or all but one.
        activityNameMatches nameToTest =
            IntDict.filterMap (matchToID nameToTest) activityNamesDict

        -- Convert the matches dict to a list and then to a single ActivityID, maybe.
        -- If for some reason there's multiple matches, choose the first.
        -- If none matched, returns nothing (List.head)
        pickFirstMatch nameToTest =
            List.head <| IntDict.values (activityNameMatches nameToTest)
    in
    -- For all projects, take the name and check it against the activityID dict
    IntDict.filterMap (\i p -> pickFirstMatch p.name) projects


timetrackItemToTask : IntDict ActivityID -> Item -> Maybe Task
timetrackItemToTask lookup item =
    -- Equivalent to the one-liner:
    --      Maybe.map (\act -> itemToTask act item) (IntDict.get item.project_id lookup)
    -- Just sayin'.
    case Debug.log "lookup" <| IntDict.get item.project_id lookup of
        Just act ->
            Just (itemToTask act item)

        Nothing ->
            Nothing


itemToTask : Activity.ActivityID -> Item -> Task
itemToTask activityID item =
    let
        base =
            newTask newName item.id

        ( newName, ( minDur, maxDur ) ) =
            extractTiming2 item.content
    in
    { base
        | completion =
            if item.checked then
                Task.Progress.maximize base.completion

            else
                base.completion
        , tags = []
        , activity = Just activityID
        , minEffort = Maybe.withDefault base.minEffort minDur
        , maxEffort = Maybe.withDefault base.maxEffort maxDur
        , importance = priorityToImportance item.priority
        , deadline = Maybe.map .date item.due
    }


priorityToImportance : Item.Priority -> Int
priorityToImportance (Item.Priority int) =
    0 - int


extractTiming : String -> ( String, ( Maybe HumanDuration, Maybe HumanDuration ) )
extractTiming name =
    let
        -- hehe, this should be fun
        lastWord =
            List.last (String.words name)

        -- All aboard the Maybe Train!
        -- result =
        --     List.foldl Maybe.andThen lastWord maybeTrain
        -- maybeTrain =
        --     [ checkParens, numberSegments, valueSegments ]
        checkParens chunk =
            if String.startsWith "(" chunk && String.endsWith ")" chunk then
                Just (String.slice 1 -1 chunk)

            else
                Nothing

        checkMinutesLabel chunk =
            let
                chunks =
                    segments chunk
            in
            if List.any (String.endsWith "m") chunks then
                Just (List.map (String.replace "m" "") chunks)

            else if List.any (String.endsWith "min") chunks then
                Just (List.map (String.replace "min" "") chunks)

            else
                Nothing

        segments chunk =
            String.split "-" chunk

        checkNumberSegments chunks =
            if List.all (String.all Char.isDigit) chunks then
                Just chunks

            else
                Nothing

        startsWithNumber chunk =
            Maybe.withDefault False <|
                Maybe.map Char.isDigit <|
                    Maybe.map Tuple.first <|
                        String.uncons chunk

        valueSegments chunks =
            List.Nonempty.fromList <| chunks

        maybeChain =
            lastWord
                |> Maybe.andThen checkParens
                |> Maybe.andThen checkMinutesLabel
                |> Maybe.andThen checkNumberSegments
                |> Maybe.andThen valueSegments
    in
    ( name, ( Nothing, Nothing ) )


extractTiming2 : String -> ( String, ( Maybe Duration, Maybe Duration ) )
extractTiming2 input =
    -- TODO optimize this sucker
    let
        chunk start =
            String.dropLeft start input

        withoutChunk chunkStart =
            String.dropRight (String.length (chunk chunkStart)) input

        default =
            ( input, ( Nothing, Nothing ) )
    in
    case List.last (String.indexes "(" input) of
        -- There were no left parens
        Nothing ->
            default

        -- found left parens! here's the index of the last one found
        Just chunkStart ->
            case Parser.run timing (chunk chunkStart) of
                Err _ ->
                    -- couldn't make out a valid glob, leave it be
                    default

                Ok ( num1, num2 ) ->
                    -- found a valid glob! remove it from title
                    ( withoutChunk chunkStart
                    , ( Just (Duration.fromMinutes num1), Just (Duration.fromMinutes num2) )
                    )


timing : Parser ( Float, Float )
timing =
    Parser.succeed Tuple.pair
        |. symbol "("
        |. spaces
        |= Parser.float
        -- TODO allow "m" after this one too
        |. symbol "-"
        |= Parser.float
        |. symbol "m"
        -- TODO allow "min" also
        |. spaces
        |. symbol ")"
