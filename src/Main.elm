port module Main exposing (main)

import Browser
import File exposing (File)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Keyed as Keyed
import Html.Events exposing (..)
import Http
import Json.Decode as D
import Json.Encode as E
import Chart as C
import Chart.Attributes as CA
import Task
import Time



-- PORTS


port saveStorage : { key : String, value : String } -> Cmd msg


port clearStorage : () -> Cmd msg


-- Bool = force consent prompt (True when user explicitly clicks Sign In,
-- False for silent re-auth after a 401)
port requestOAuthToken : Bool -> Cmd msg


port gotNewToken : (String -> msg) -> Sub msg



-- TYPES


type Category
    = Fuel
    | Food
    | Camp
    | Ferry
    | Gear
    | Misc


type Tab
    = ScanTab
    | AddTab
    | LedgerTab
    | StatsTab
    | SettingsTab


type alias Entry =
    { id : String
    , date : String
    , amount : Float
    , category : Category
    , note : String
    , merchant : String
    , createdAt : String
    , rowIndex : Int
    }


type alias PendingEntry =
    { amount : String
    , category : Category
    , note : String
    , merchant : String
    , date : String
    }


type alias Model =
    { tab : Tab
    , oauthToken : Maybe String
    , sheetId : String
    , googleClientId : String
    , anthropicKey : String
    , tripStart : String
    , entries : List Entry
    , loadingEntries : Bool
    , pendingEntry : PendingEntry
    , scanImage : Maybe String
    , scanLoading : Bool
    , error : Maybe String
    , submitting : Bool
    , today : String
    }


type Msg
    = GotOAuthToken String
    | SignInClicked
    | SignOutClicked
    | FileSelected File
    | GotFileUrl String
    | GotOcrResult (Result Http.Error String)
    | AmountChanged String
    | CategorySelected Category
    | NoteChanged String
    | MerchantChanged String
    | DateChanged String
    | SubmitEntry
    | GotSubmitTime Time.Posix
    | EntrySubmitted (Result Http.Error ())
    | EntriesFetched (Result Http.Error (List Entry))
    | DeleteEntry Entry
    | EntryDeleted (Result Http.Error ())
    | TabChanged Tab
    | ApiKeyChanged String
    | SheetIdChanged String
    | GoogleClientIdChanged String
    | TripStartChanged String
    | RefreshClicked
    | DismissError



-- CATEGORY HELPERS


categoryColor : Category -> String
categoryColor cat =
    case cat of
        Fuel -> "#e8a020"
        Food -> "#3ecf6a"
        Camp -> "#4090e0"
        Ferry -> "#c060e0"
        Gear -> "#e85030"
        Misc -> "#7a8a80"


categoryLabel : Category -> String
categoryLabel cat =
    case cat of
        Fuel -> "fuel"
        Food -> "food"
        Camp -> "camp"
        Ferry -> "ferry"
        Gear -> "gear"
        Misc -> "misc"


categoryIcon : Category -> String
categoryIcon cat =
    case cat of
        Fuel -> "⛽"
        Food -> "🍔"
        Camp -> "⛺"
        Ferry -> "⛴"
        Gear -> "🔧"
        Misc -> "📦"


categoryFromString : String -> Category
categoryFromString s =
    case s of
        "fuel" -> Fuel
        "food" -> Food
        "camp" -> Camp
        "ferry" -> Ferry
        "gear" -> Gear
        _ -> Misc


allCategories : List Category
allCategories =
    [ Fuel, Food, Camp, Ferry, Gear, Misc ]


ocrSystemPrompt : String
ocrSystemPrompt =
    "You are a receipt parser. Extract expense info and return ONLY raw valid JSON with no markdown, no code fences, no explanation. Format exactly: {\"amount\": <number>, \"category\": \"<fuel|food|camp|ferry|gear|misc>\", \"note\": \"<brief description max 50 chars>\", \"merchant\": \"<store name>\"}. Choose the best matching category."



-- INIT


defaultPendingEntry : String -> PendingEntry
defaultPendingEntry today =
    { amount = "", category = Fuel, note = "", merchant = "", date = today }


init : D.Value -> ( Model, Cmd Msg )
init flagsJson =
    let
        dec field_ =
            D.decodeValue (D.field field_ D.string) flagsJson
                |> Result.withDefault ""

        token =
            D.decodeValue (D.maybe (D.field "token" D.string)) flagsJson
                |> Result.withDefault Nothing
                |> Maybe.andThen
                    (\t ->
                        if t == "" then
                            Nothing

                        else
                            Just t
                    )

        sheetId =
            dec "sheetId"

        today =
            dec "today"

        model =
            { tab = LedgerTab
            , oauthToken = token
            , sheetId = sheetId
            , googleClientId = dec "googleClientId"
            , anthropicKey = dec "anthropicKey"
            , tripStart = dec "tripStart" |> (\s -> if s == "" then "2026-05-22" else s)
            , entries = []
            , loadingEntries = False
            , pendingEntry = defaultPendingEntry today
            , scanImage = Nothing
            , scanLoading = False
            , error = Nothing
            , submitting = False
            , today = today
            }

        fetchCmd =
            case token of
                Just t ->
                    if sheetId /= "" then
                        fetchEntries t sheetId

                    else
                        Cmd.none

                Nothing ->
                    Cmd.none
    in
    ( { model | loadingEntries = fetchCmd /= Cmd.none }
    , fetchCmd
    )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SignInClicked ->
            if model.googleClientId == "" then
                ( { model | error = Just "Enter your Google Client ID in Settings first." }
                , Cmd.none
                )

            else
                ( model, requestOAuthToken True )

        GotOAuthToken token ->
            let
                shouldFetch =
                    model.sheetId /= ""
            in
            ( { model | oauthToken = Just token, loadingEntries = shouldFetch }
            , Cmd.batch
                [ saveStorage { key = "oauth_token", value = token }
                , if shouldFetch then fetchEntries token model.sheetId else Cmd.none
                ]
            )

        SignOutClicked ->
            ( { model
                | oauthToken = Nothing
                , entries = []
                , tab = LedgerTab
              }
            , clearStorage ()
            )

        FileSelected file ->
            ( { model | scanLoading = True, scanImage = Nothing, error = Nothing }
            , Task.perform GotFileUrl (File.toUrl file)
            )

        GotFileUrl dataUrl ->
            if model.anthropicKey == "" then
                ( { model | scanLoading = False, scanImage = Just dataUrl, error = Just "No Anthropic API key — enter it in Settings or fill form manually.", tab = AddTab }
                , Cmd.none
                )

            else
                ( { model | scanImage = Just dataUrl }
                , makeOcrCall model.anthropicKey (extractBase64 dataUrl) (getMimeType dataUrl)
                )

        GotOcrResult result ->
            case result of
                Err e ->
                    ( { model | scanLoading = False, error = Just ("OCR failed: " ++ httpErrString e), tab = AddTab }
                    , Cmd.none
                    )

                Ok responseBody ->
                    case D.decodeString claudeTextDecoder responseBody of
                        Err _ ->
                            ( { model | scanLoading = False, error = Just "Could not parse OCR response — fill form manually.", tab = AddTab }
                            , Cmd.none
                            )

                        Ok innerJson ->
                            case D.decodeString ocrDataDecoder (stripCodeFence innerJson) of
                                Err _ ->
                                    ( { model | scanLoading = False, error = Just "Could not read receipt data — fill form manually.", tab = AddTab }
                                    , Cmd.none
                                    )

                                Ok ocrData ->
                                    let
                                        p =
                                            model.pendingEntry

                                        updated =
                                            { p
                                                | amount = ocrData.amount |> Maybe.map (\a -> String.fromFloat a) |> Maybe.withDefault p.amount
                                                , category = Maybe.withDefault p.category ocrData.category
                                                , note = Maybe.withDefault p.note ocrData.note
                                                , merchant = Maybe.withDefault p.merchant ocrData.merchant
                                            }
                                    in
                                    ( { model | scanLoading = False, pendingEntry = updated, tab = AddTab }
                                    , Cmd.none
                                    )

        AmountChanged s ->
            updatePending (\p -> { p | amount = s }) model

        CategorySelected cat ->
            updatePending (\p -> { p | category = cat }) model

        NoteChanged s ->
            updatePending (\p -> { p | note = s }) model

        MerchantChanged s ->
            updatePending (\p -> { p | merchant = s }) model

        DateChanged s ->
            updatePending (\p -> { p | date = s }) model

        SubmitEntry ->
            case ( model.oauthToken, String.toFloat model.pendingEntry.amount ) of
                ( Just _, Just _ ) ->
                    ( { model | submitting = True, error = Nothing }
                    , Task.perform GotSubmitTime Time.now
                    )

                ( Nothing, _ ) ->
                    ( { model | error = Just "Not signed in." }, Cmd.none )

                ( _, Nothing ) ->
                    ( { model | error = Just "Enter a valid amount." }, Cmd.none )

        GotSubmitTime posix ->
            let
                p =
                    model.pendingEntry

                entry =
                    { id = "e-" ++ String.fromInt (Time.posixToMillis posix)
                    , date = p.date
                    , amount = String.toFloat p.amount |> Maybe.withDefault 0
                    , category = p.category
                    , note = p.note
                    , merchant = p.merchant
                    , createdAt = posixToIso posix
                    , rowIndex = 0
                    }

                token =
                    Maybe.withDefault "" model.oauthToken
            in
            ( model
            , appendEntry token model.sheetId entry
            )

        EntrySubmitted result ->
            case result of
                Ok () ->
                    ( { model
                        | submitting = False
                        , pendingEntry = defaultPendingEntry model.today
                        , tab = LedgerTab
                        , loadingEntries = True
                      }
                    , fetchEntries (Maybe.withDefault "" model.oauthToken) model.sheetId
                    )

                Err (Http.BadStatus 401) ->
                    ( { model | submitting = False }, requestOAuthToken False )

                Err e ->
                    ( { model | submitting = False, error = Just ("Save failed: " ++ httpErrString e) }
                    , Cmd.none
                    )

        EntriesFetched result ->
            case result of
                Ok entries ->
                    ( { model | entries = entries, loadingEntries = False }
                    , Cmd.none
                    )

                Err (Http.BadStatus 401) ->
                    ( { model | loadingEntries = False }, requestOAuthToken False )

                Err e ->
                    ( { model | loadingEntries = False, error = Just ("Load failed: " ++ httpErrString e) }
                    , Cmd.none
                    )

        DeleteEntry entry ->
            ( { model | entries = List.filter (\e -> e.id /= entry.id) model.entries }
            , deleteEntry (Maybe.withDefault "" model.oauthToken) model.sheetId entry.rowIndex
            )

        EntryDeleted result ->
            case result of
                Ok () ->
                    ( model, fetchEntries (Maybe.withDefault "" model.oauthToken) model.sheetId )

                Err (Http.BadStatus 401) ->
                    ( model, requestOAuthToken False )

                Err e ->
                    ( { model | error = Just ("Delete failed: " ++ httpErrString e) }
                    , Cmd.none
                    )

        TabChanged tab ->
            let
                shouldFetch =
                    tab == LedgerTab && model.oauthToken /= Nothing && model.sheetId /= ""
            in
            ( { model | tab = tab, loadingEntries = shouldFetch }
            , if shouldFetch then
                fetchEntries (Maybe.withDefault "" model.oauthToken) model.sheetId

              else
                Cmd.none
            )

        RefreshClicked ->
            ( { model | loadingEntries = True }
            , fetchEntries (Maybe.withDefault "" model.oauthToken) model.sheetId
            )

        ApiKeyChanged s ->
            ( { model | anthropicKey = s }
            , saveStorage { key = "anthropic_key", value = s }
            )

        SheetIdChanged s ->
            ( { model | sheetId = s }
            , saveStorage { key = "sheet_id", value = s }
            )

        GoogleClientIdChanged s ->
            ( { model | googleClientId = s }
            , saveStorage { key = "google_client_id", value = s }
            )

        TripStartChanged s ->
            ( { model | tripStart = s }
            , saveStorage { key = "trip_start", value = s }
            )

        DismissError ->
            ( { model | error = Nothing }, Cmd.none )


updatePending : (PendingEntry -> PendingEntry) -> Model -> ( Model, Cmd Msg )
updatePending f model =
    ( { model | pendingEntry = f model.pendingEntry }, Cmd.none )



-- HTTP


fetchEntries : String -> String -> Cmd Msg
fetchEntries token sheetId =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "https://sheets.googleapis.com/v4/spreadsheets/" ++ sheetId ++ "/values/Expenses!A2:G"
        , body = Http.emptyBody
        , expect = expectJsonBody EntriesFetched entriesDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


appendEntry : String -> String -> Entry -> Cmd Msg
appendEntry token sheetId entry =
    let
        body =
            E.object
                [ ( "values"
                  , E.list identity
                        [ E.list identity
                            [ E.string entry.id
                            , E.string entry.date
                            , E.float entry.amount
                            , E.string (categoryLabel entry.category)
                            , E.string entry.note
                            , E.string entry.merchant
                            , E.string entry.createdAt
                            ]
                        ]
                  )
                ]
    in
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "https://sheets.googleapis.com/v4/spreadsheets/" ++ sheetId ++ "/values/Expenses!A:G:append?valueInputOption=RAW"
        , body = Http.jsonBody body
        , expect = expectWhateverBody EntrySubmitted
        , timeout = Nothing
        , tracker = Nothing
        }


deleteEntry : String -> String -> Int -> Cmd Msg
deleteEntry token sheetId rowIndex =
    let
        body =
            E.object
                [ ( "requests"
                  , E.list identity
                        [ E.object
                            [ ( "deleteDimension"
                              , E.object
                                    [ ( "range"
                                      , E.object
                                            [ ( "sheetId", E.int 0 )
                                            , ( "dimension", E.string "ROWS" )
                                            , ( "startIndex", E.int (rowIndex - 1) )
                                            , ( "endIndex", E.int rowIndex )
                                            ]
                                      )
                                    ]
                              )
                            ]
                        ]
                  )
                ]
    in
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "https://sheets.googleapis.com/v4/spreadsheets/" ++ sheetId ++ ":batchUpdate"
        , body = Http.jsonBody body
        , expect = expectWhateverBody EntryDeleted
        , timeout = Nothing
        , tracker = Nothing
        }


makeOcrCall : String -> String -> String -> Cmd Msg
makeOcrCall apiKey base64Data mimeType =
    let
        body =
            E.object
                [ ( "model", E.string "claude-sonnet-4-6" )
                , ( "max_tokens", E.int 256 )
                , ( "system", E.string ocrSystemPrompt )
                , ( "messages"
                  , E.list identity
                        [ E.object
                            [ ( "role", E.string "user" )
                            , ( "content"
                              , E.list identity
                                    [ E.object
                                        [ ( "type", E.string "image" )
                                        , ( "source"
                                          , E.object
                                                [ ( "type", E.string "base64" )
                                                , ( "media_type", E.string mimeType )
                                                , ( "data", E.string base64Data )
                                                ]
                                          )
                                        ]
                                    , E.object
                                        [ ( "type", E.string "text" )
                                        , ( "text", E.string "Extract the expense info from this receipt." )
                                        ]
                                    ]
                              )
                            ]
                        ]
                  )
                ]
    in
    Http.request
        { method = "POST"
        , headers =
            [ Http.header "x-api-key" apiKey
            , Http.header "anthropic-version" "2023-06-01"
            , Http.header "anthropic-dangerous-direct-browser-access" "true"
            ]
        , url = "https://api.anthropic.com/v1/messages"
        , body = Http.jsonBody body
        , expect = Http.expectString GotOcrResult
        , timeout = Nothing
        , tracker = Nothing
        }



-- CUSTOM HTTP EXPECT HELPERS
-- Both preserve 401 as Http.BadStatus 401 (so Elm can trigger silent re-auth)
-- and fold all other errors into Http.BadBody with the response body included.


expectJsonBody : (Result Http.Error a -> msg) -> D.Decoder a -> Http.Expect msg
expectJsonBody toMsg decoder =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.BadUrl_ u ->
                    Err (Http.BadUrl u)

                Http.Timeout_ ->
                    Err Http.Timeout

                Http.NetworkError_ ->
                    Err Http.NetworkError

                Http.BadStatus_ meta body ->
                    if meta.statusCode == 401 then
                        Err (Http.BadStatus 401)

                    else
                        Err (Http.BadBody (String.fromInt meta.statusCode ++ " " ++ body))

                Http.GoodStatus_ _ body ->
                    case D.decodeString decoder body of
                        Ok v ->
                            Ok v

                        Err e ->
                            Err (Http.BadBody (D.errorToString e))


expectWhateverBody : (Result Http.Error () -> msg) -> Http.Expect msg
expectWhateverBody toMsg =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.BadUrl_ u ->
                    Err (Http.BadUrl u)

                Http.Timeout_ ->
                    Err Http.Timeout

                Http.NetworkError_ ->
                    Err Http.NetworkError

                Http.BadStatus_ meta body ->
                    if meta.statusCode == 401 then
                        Err (Http.BadStatus 401)

                    else
                        Err (Http.BadBody (String.fromInt meta.statusCode ++ " " ++ body))

                Http.GoodStatus_ _ _ ->
                    Ok ()


-- DECODERS


entriesDecoder : D.Decoder (List Entry)
entriesDecoder =
    D.oneOf
        [ D.field "values" (D.list rowDecoder)
            |> D.map (List.indexedMap (\i e -> { e | rowIndex = i + 2 }))
        , D.succeed []
        ]


rowDecoder : D.Decoder Entry
rowDecoder =
    D.map7
        (\id date amount category note merchant createdAt ->
            { id = id
            , date = date
            , amount = amount
            , category = category
            , note = note
            , merchant = merchant
            , createdAt = createdAt
            , rowIndex = 0
            }
        )
        (D.index 0 D.string)
        (D.index 1 D.string)
        (D.index 2 (D.string |> D.andThen parseAmountStr))
        (D.index 3 (D.string |> D.map categoryFromString))
        (optIndex 4 D.string "")
        (optIndex 5 D.string "")
        (optIndex 6 D.string "")


optIndex : Int -> D.Decoder a -> a -> D.Decoder a
optIndex i decoder fallback =
    D.oneOf
        [ D.index i decoder
        , D.succeed fallback
        ]


parseAmountStr : String -> D.Decoder Float
parseAmountStr s =
    case String.toFloat s of
        Just f ->
            D.succeed f

        Nothing ->
            D.succeed 0.0


claudeTextDecoder : D.Decoder String
claudeTextDecoder =
    D.field "content" (D.index 0 (D.field "text" D.string))


type alias OcrData =
    { amount : Maybe Float
    , category : Maybe Category
    , note : Maybe String
    , merchant : Maybe String
    }


ocrDataDecoder : D.Decoder OcrData
ocrDataDecoder =
    D.map4 OcrData
        (D.maybe (D.field "amount" D.float))
        (D.maybe (D.field "category" (D.string |> D.map categoryFromString)))
        (D.maybe (D.field "note" D.string))
        (D.maybe (D.field "merchant" D.string))



-- TIME / URL HELPERS


posixToIso : Time.Posix -> String
posixToIso posix =
    let
        y =
            String.fromInt (Time.toYear Time.utc posix)

        m =
            String.fromInt (monthNum (Time.toMonth Time.utc posix)) |> String.padLeft 2 '0'

        d =
            String.fromInt (Time.toDay Time.utc posix) |> String.padLeft 2 '0'

        h =
            String.fromInt (Time.toHour Time.utc posix) |> String.padLeft 2 '0'

        mi =
            String.fromInt (Time.toMinute Time.utc posix) |> String.padLeft 2 '0'

        s =
            String.fromInt (Time.toSecond Time.utc posix) |> String.padLeft 2 '0'
    in
    y ++ "-" ++ m ++ "-" ++ d ++ "T" ++ h ++ ":" ++ mi ++ ":" ++ s ++ "Z"


monthNum : Time.Month -> Int
monthNum month =
    case month of
        Time.Jan -> 1
        Time.Feb -> 2
        Time.Mar -> 3
        Time.Apr -> 4
        Time.May -> 5
        Time.Jun -> 6
        Time.Jul -> 7
        Time.Aug -> 8
        Time.Sep -> 9
        Time.Oct -> 10
        Time.Nov -> 11
        Time.Dec -> 12


formatDateDisplay : String -> String
formatDateDisplay iso =
    case String.split "-" iso of
        [ y, m, d ] ->
            let
                mn =
                    case m of
                        "01" -> "Jan"
                        "02" -> "Feb"
                        "03" -> "Mar"
                        "04" -> "Apr"
                        "05" -> "May"
                        "06" -> "Jun"
                        "07" -> "Jul"
                        "08" -> "Aug"
                        "09" -> "Sep"
                        "10" -> "Oct"
                        "11" -> "Nov"
                        "12" -> "Dec"
                        _ -> m

                day =
                    String.toInt d |> Maybe.withDefault 0 |> String.fromInt
            in
            mn ++ " " ++ day ++ ", " ++ y

        _ ->
            iso



stripCodeFence : String -> String
stripCodeFence s =
    let
        trimmed =
            String.trim s
    in
    if String.startsWith "```" trimmed then
        trimmed
            |> String.lines
            |> List.drop 1
            |> (\lines ->
                    if List.reverse lines |> List.head |> Maybe.map (String.startsWith "```") |> Maybe.withDefault False then
                        List.reverse lines |> List.drop 1 |> List.reverse
                    else
                        lines
               )
            |> String.join "\n"
            |> String.trim
    else
        trimmed


extractBase64 : String -> String
extractBase64 dataUrl =
    case String.split "," dataUrl of
        _ :: b64 :: _ ->
            b64

        _ ->
            dataUrl


getMimeType : String -> String
getMimeType dataUrl =
    if String.contains "image/png" dataUrl then
        "image/png"

    else if String.contains "image/gif" dataUrl then
        "image/gif"

    else if String.contains "image/webp" dataUrl then
        "image/webp"

    else
        "image/jpeg"


httpErrString : Http.Error -> String
httpErrString err =
    case err of
        Http.BadUrl u ->
            "Bad URL: " ++ u

        Http.Timeout ->
            "Request timed out"

        Http.NetworkError ->
            "No network connection"

        Http.BadStatus 401 ->
            "Session expired — re-authenticating…"

        Http.BadStatus code ->
            "HTTP " ++ String.fromInt code

        Http.BadBody body ->
            -- body is "NNN <json>"; try to extract Google's message field
            let
                jsonPart =
                    body |> String.dropLeft 4 |> String.trimLeft
            in
            D.decodeString (D.at [ "error", "message" ] D.string) jsonPart
                |> Result.withDefault (String.left 160 body)


formatAmount : Float -> String
formatAmount amount =
    let
        cents =
            round (amount * 100)

        dollars =
            cents // 100

        centsRem =
            remainderBy 100 (abs cents)
    in
    "$" ++ String.fromInt dollars ++ "." ++ String.padLeft 2 '0' (String.fromInt centsRem)


uniqueDates : List Entry -> List String
uniqueDates entries =
    entries
        |> List.map .date
        |> List.foldr
            (\d acc ->
                if List.member d acc then
                    acc

                else
                    d :: acc
            )
            []
        |> List.sort
        |> List.reverse


medianAmount : List Entry -> Float
medianAmount entries =
    let
        amounts =
            List.sort (List.map .amount entries)

        n =
            List.length amounts

        mid =
            n // 2
    in
    if n == 0 then
        0

    else if remainderBy 2 n == 1 then
        amounts |> List.drop mid |> List.head |> Maybe.withDefault 0

    else
        let
            a =
                amounts |> List.drop (mid - 1) |> List.head |> Maybe.withDefault 0

            b =
                amounts |> List.drop mid |> List.head |> Maybe.withDefault 0
        in
        (a + b) / 2


topCategory : List Entry -> Maybe Category
topCategory entries =
    allCategories
        |> List.map
            (\cat ->
                ( cat
                , entries
                    |> List.filter (\e -> e.category == cat)
                    |> List.map .amount
                    |> List.sum
                )
            )
        |> List.sortBy (negate << Tuple.second)
        |> List.head
        |> Maybe.andThen
            (\( cat, total ) ->
                if total > 0 then
                    Just cat

                else
                    Nothing
            )


biggestDay : List Entry -> Maybe ( String, Float )
biggestDay entries =
    uniqueDates entries
        |> List.map
            (\date ->
                ( date
                , entries
                    |> List.filter (\e -> e.date == date)
                    |> List.map .amount
                    |> List.sum
                )
            )
        |> List.sortBy (negate << Tuple.second)
        |> List.head



-- VIEW


view : Model -> Html Msg
view model =
    div
        [ style "background" "#0d0f0e"
        , style "color" "#c8d0c8"
        , style "min-height" "100vh"
        , style "font-family" "'Barlow Condensed', system-ui, sans-serif"
        , style "max-width" "480px"
        , style "margin" "0 auto"
        , style "position" "relative"
        ]
        [ case model.oauthToken of
            Nothing ->
                viewSignIn model

            Just _ ->
                viewApp model
        ]


viewSignIn : Model -> Html Msg
viewSignIn model =
    div
        [ style "display" "flex"
        , style "flex-direction" "column"
        , style "align-items" "center"
        , style "justify-content" "center"
        , style "min-height" "100vh"
        , style "padding" "32px 24px"
        , style "text-align" "center"
        ]
        [ div [ style "font-size" "48px", style "margin-bottom" "16px" ] [ text "🏔" ]
        , h1
            [ style "font-size" "32px"
            , style "font-weight" "700"
            , style "color" "#e8a020"
            , style "letter-spacing" "0.05em"
            , style "margin-bottom" "8px"
            ]
            [ text "ALASKA TRACKER" ]
        , p [ style "color" "#7a8a80", style "margin-bottom" "48px", style "font-size" "16px" ]
            [ text "Road log for the long way north" ]
        , viewErrorBanner model
        , button
            [ onClick SignInClicked
            , style "background" "#e8a020"
            , style "color" "#0d0f0e"
            , style "border" "none"
            , style "border-radius" "8px"
            , style "padding" "16px 32px"
            , style "font-size" "16px"
            , style "font-weight" "700"
            , style "cursor" "pointer"
            , style "letter-spacing" "0.05em"
            , style "min-height" "52px"
            ]
            [ text "SIGN IN WITH GOOGLE" ]
        , p [ style "color" "#4a5a50", style "margin-top" "24px", style "font-size" "13px" ]
            [ text "Need a Google Client ID? Enter it in Settings below." ]
        , div [ style "margin-top" "48px", style "width" "100%" ]
            [ button
                [ onClick (TabChanged SettingsTab)
                , style "background" "none"
                , style "border" "1px solid #3a4240"
                , style "color" "#7a8a80"
                , style "border-radius" "6px"
                , style "padding" "10px 20px"
                , style "font-size" "14px"
                , style "cursor" "pointer"
                ]
                [ text "⚙ Settings" ]
            , if model.tab == SettingsTab then
                viewSettingsTab model

              else
                text ""
            ]
        ]


viewApp : Model -> Html Msg
viewApp model =
    div []
        [ viewHeader model
        , viewErrorBanner model
        , div [ style "padding-bottom" "80px" ]
            [ case model.tab of
                ScanTab ->
                    viewScanTab model

                AddTab ->
                    viewAddTab model

                LedgerTab ->
                    viewLedgerTab model

                StatsTab ->
                    viewStatsTab model

                SettingsTab ->
                    viewSettingsTab model
            ]
        , viewBottomNav model.tab
        ]


viewHeader : Model -> Html Msg
viewHeader model =
    div
        [ style "background" "#161918"
        , style "border-bottom" "1px solid #2a3230"
        , style "padding" "12px 20px"
        , style "display" "flex"
        , style "align-items" "center"
        , style "justify-content" "space-between"
        , style "position" "sticky"
        , style "top" "0"
        , style "z-index" "10"
        ]
        [ span
            [ style "font-size" "18px"
            , style "font-weight" "700"
            , style "color" "#e8a020"
            , style "letter-spacing" "0.08em"
            ]
            [ text "ALASKA" ]
        , button
            [ onClick
                (if model.tab == SettingsTab then
                    TabChanged LedgerTab

                 else
                    TabChanged SettingsTab
                )
            , style "background" "none"
            , style "border" "none"
            , style "font-size" "22px"
            , style "cursor" "pointer"
            , style "padding" "4px 8px"
            , style "color" (if model.tab == SettingsTab then "#e8a020" else "#7a8a80")
            ]
            [ text "⚙" ]
        ]


viewBottomNav : Tab -> Html Msg
viewBottomNav currentTab =
    nav
        [ style "position" "fixed"
        , style "bottom" "0"
        , style "left" "50%"
        , style "transform" "translateX(-50%)"
        , style "width" "100%"
        , style "max-width" "480px"
        , style "background" "#161918"
        , style "border-top" "1px solid #2a3230"
        , style "display" "flex"
        , style "z-index" "10"
        ]
        (List.map (viewNavTab currentTab)
            [ ( ScanTab, "📷", "Scan" )
            , ( AddTab, "+", "Add" )
            , ( LedgerTab, "☰", "Ledger" )
            , ( StatsTab, "▦", "Stats" )
            ]
        )


viewNavTab : Tab -> ( Tab, String, String ) -> Html Msg
viewNavTab currentTab ( tab, icon, label_ ) =
    let
        active =
            currentTab == tab
    in
    button
        [ onClick (TabChanged tab)
        , style "flex" "1"
        , style "background" "none"
        , style "border" "none"
        , style "padding" "10px 4px"
        , style "display" "flex"
        , style "flex-direction" "column"
        , style "align-items" "center"
        , style "gap" "2px"
        , style "cursor" "pointer"
        , style "color" (if active then "#e8a020" else "#7a8a80")
        , style "min-height" "56px"
        ]
        [ span [ style "font-size" "20px" ] [ text icon ]
        , span [ style "font-size" "10px", style "letter-spacing" "0.05em" ] [ text label_ ]
        ]



-- SCAN TAB


viewScanTab : Model -> Html Msg
viewScanTab model =
    div [ style "padding" "24px 20px" ]
        [ h2 [ sectionHead ] [ text "SCAN RECEIPT" ]
        , if model.scanLoading then
            div
                [ style "text-align" "center"
                , style "padding" "48px"
                , style "color" "#e8a020"
                ]
                [ div [ style "font-size" "32px", style "margin-bottom" "12px" ] [ text "⏳" ]
                , p [] [ text "Reading receipt..." ]
                ]

          else
            div []
                [ label
                    [ style "display" "flex"
                    , style "flex-direction" "column"
                    , style "align-items" "center"
                    , style "justify-content" "center"
                    , style "background" "#1e2220"
                    , style "border" "2px dashed #3a4240"
                    , style "border-radius" "12px"
                    , style "padding" "48px 24px"
                    , style "cursor" "pointer"
                    , style "margin-bottom" "20px"
                    , style "min-height" "160px"
                    ]
                    [ div [ style "font-size" "48px", style "margin-bottom" "12px" ] [ text "📷" ]
                    , p [ style "color" "#7a8a80", style "font-size" "16px" ] [ text "Tap to photograph receipt" ]
                    , input
                        [ type_ "file"
                        , accept "image/*"
                        , attribute "capture" "environment"
                        , style "display" "none"
                        , on "change" (D.map FileSelected (D.at [ "target", "files", "0" ] File.decoder))
                        ]
                        []
                    ]
                , case model.scanImage of
                    Just dataUrl ->
                        img
                            [ src dataUrl
                            , style "width" "100%"
                            , style "border-radius" "8px"
                            , style "margin-bottom" "16px"
                            ]
                            []

                    Nothing ->
                        text ""
                , button
                    [ onClick (TabChanged AddTab)
                    , style "width" "100%"
                    , style "background" "none"
                    , style "border" "1px solid #3a4240"
                    , style "color" "#7a8a80"
                    , style "border-radius" "8px"
                    , style "padding" "14px"
                    , style "font-size" "15px"
                    , style "cursor" "pointer"
                    ]
                    [ text "Fill in manually →" ]
                ]
        ]



-- ADD TAB


viewAddTab : Model -> Html Msg
viewAddTab model =
    let
        p =
            model.pendingEntry
    in
    div [ style "padding" "24px 20px" ]
        [ h2 [ sectionHead ] [ text "ADD EXPENSE" ]
        , formField "AMOUNT"
            (div [ style "position" "relative" ]
                [ span
                    [ style "position" "absolute"
                    , style "left" "14px"
                    , style "top" "50%"
                    , style "transform" "translateY(-50%)"
                    , style "color" "#e8a020"
                    , style "font-size" "20px"
                    , style "font-family" "monospace"
                    ]
                    [ text "$" ]
                , input
                    [ type_ "number"
                    , attribute "inputmode" "decimal"
                    , value p.amount
                    , onInput AmountChanged
                    , placeholder "0.00"
                    , style "width" "100%"
                    , style "background" "#1e2220"
                    , style "border" "1px solid #3a4240"
                    , style "color" "#c8d0c8"
                    , style "border-radius" "8px"
                    , style "padding" "16px 14px 16px 36px"
                    , style "font-size" "24px"
                    , style "font-family" "monospace"
                    ]
                    []
                ]
            )
        , formField "CATEGORY"
            (div
                [ style "display" "grid"
                , style "grid-template-columns" "repeat(3, 1fr)"
                , style "gap" "8px"
                ]
                (List.map (viewCategoryBtn p.category) allCategories)
            )
        , formField "NOTE"
            (input
                [ type_ "text"
                , value p.note
                , onInput NoteChanged
                , placeholder "optional"
                , textInputStyle
                ]
                []
            )
        , formField "MERCHANT"
            (input
                [ type_ "text"
                , value p.merchant
                , onInput MerchantChanged
                , placeholder "optional"
                , textInputStyle
                ]
                []
            )
        , formField "DATE"
            (input
                [ type_ "date"
                , value p.date
                , onInput DateChanged
                , textInputStyle
                ]
                []
            )
        , button
            [ onClick SubmitEntry
            , disabled model.submitting
            , style "width" "100%"
            , style "background" "#e8a020"
            , style "color" "#0d0f0e"
            , style "border" "none"
            , style "border-radius" "8px"
            , style "padding" "18px"
            , style "font-size" "18px"
            , style "font-weight" "700"
            , style "letter-spacing" "0.05em"
            , style "cursor" (if model.submitting then "not-allowed" else "pointer")
            , style "margin-top" "8px"
            , style "min-height" "56px"
            , style "opacity" (if model.submitting then "0.6" else "1")
            ]
            [ text (if model.submitting then "SAVING..." else "SAVE EXPENSE") ]
        ]


viewCategoryBtn : Category -> Category -> Html Msg
viewCategoryBtn selected cat =
    let
        active =
            selected == cat
    in
    button
        [ onClick (CategorySelected cat)
        , style "background" (if active then categoryColor cat else "#1e2220")
        , style "color" (if active then "#0d0f0e" else "#c8d0c8")
        , style "border" ("1px solid " ++ (if active then categoryColor cat else "#3a4240"))
        , style "border-radius" "8px"
        , style "padding" "12px 8px"
        , style "font-size" "14px"
        , style "font-weight" (if active then "700" else "400")
        , style "cursor" "pointer"
        , style "display" "flex"
        , style "flex-direction" "column"
        , style "align-items" "center"
        , style "gap" "4px"
        , style "min-height" "64px"
        ]
        [ span [ style "font-size" "20px" ] [ text (categoryIcon cat) ]
        , text (categoryLabel cat)
        ]



-- LEDGER TAB


viewLedgerSummary : List Entry -> Html Msg
viewLedgerSummary entries =
    let
        total =
            List.sum (List.map .amount entries)

        catRow =
            allCategories
                |> List.filterMap
                    (\cat ->
                        let
                            t =
                                entries
                                    |> List.filter (\e -> e.category == cat)
                                    |> List.map .amount
                                    |> List.sum
                        in
                        if t > 0 then
                            Just ( cat, t )
                        else
                            Nothing
                    )
    in
    div
        [ style "background" "#161918"
        , style "border-radius" "10px"
        , style "padding" "14px 16px"
        , style "margin-bottom" "20px"
        ]
        [ div
            [ style "font-family" "monospace"
            , style "font-size" "22px"
            , style "color" "#e8a020"
            , style "margin-bottom" "12px"
            ]
            [ text (formatAmount total) ]
        , div
            [ style "display" "flex"
            , style "flex-wrap" "wrap"
            , style "gap" "10px"
            ]
            (List.map
                (\( cat, t ) ->
                    div
                        [ style "display" "flex"
                        , style "align-items" "center"
                        , style "gap" "4px"
                        ]
                        [ span [ style "font-size" "15px" ] [ text (categoryIcon cat) ]
                        , span
                            [ style "font-family" "monospace"
                            , style "font-size" "13px"
                            , style "color" "#7a8a80"
                            ]
                            [ text (formatAmount t) ]
                        ]
                )
                catRow
            )
        ]


viewLedgerTab : Model -> Html Msg
viewLedgerTab model =
    div [ style "padding" "20px" ]
        [ div
            [ style "display" "flex"
            , style "align-items" "center"
            , style "justify-content" "space-between"
            , style "margin-bottom" "20px"
            ]
            [ h2 [ sectionHead ] [ text "LEDGER" ]
            , button
                [ onClick RefreshClicked
                , style "background" "none"
                , style "border" "1px solid #3a4240"
                , style "color" "#7a8a80"
                , style "border-radius" "6px"
                , style "padding" "6px 12px"
                , style "font-size" "13px"
                , style "cursor" "pointer"
                ]
                [ text "↻ refresh" ]
            ]
        , if not (List.isEmpty model.entries) then
            viewLedgerSummary model.entries

          else
            text ""
        , if model.sheetId == "" then
            p [ style "color" "#7a8a80", style "text-align" "center", style "padding" "32px 0" ]
                [ text "Enter your Sheet ID in Settings to get started." ]

          else if model.loadingEntries then
            viewSkeleton

          else if List.isEmpty model.entries then
            p [ style "color" "#7a8a80", style "text-align" "center", style "padding" "32px 0" ]
                [ text "No expenses yet. Add your first one!" ]

          else
            Keyed.node "div"
                []
                (uniqueDates model.entries
                    |> List.map
                        (\date ->
                            let
                                dayEntries =
                                    List.filter (\e -> e.date == date) model.entries
                            in
                            ( date
                            , div [ style "margin-bottom" "24px" ]
                                [ div
                                    [ style "font-size" "11px"
                                    , style "letter-spacing" "0.1em"
                                    , style "color" "#7a8a80"
                                    , style "margin-bottom" "8px"
                                    , style "padding-bottom" "6px"
                                    , style "border-bottom" "1px solid #2a3230"
                                    , style "display" "flex"
                                    , style "justify-content" "space-between"
                                    , style "align-items" "center"
                                    ]
                                    [ text (String.toUpper (formatDateDisplay date))
                                    , span
                                        [ style "font-family" "monospace"
                                        , style "color" "#e8a020"
                                        , style "letter-spacing" "0"
                                        ]
                                        [ text (formatAmount (List.sum (List.map .amount dayEntries))) ]
                                    ]
                                , Keyed.node "div" [] (List.map (\e -> ( e.id, viewEntryRow e )) dayEntries)
                                ]
                            )
                        )
                )
        ]


viewEntryRow : Entry -> Html Msg
viewEntryRow entry =
    div
        [ style "background" "#161918"
        , style "border-radius" "8px"
        , style "padding" "14px 16px"
        , style "margin-bottom" "8px"
        , style "display" "flex"
        , style "align-items" "center"
        , style "gap" "12px"
        ]
        [ div
            [ style "width" "10px"
            , style "height" "10px"
            , style "border-radius" "50%"
            , style "background" (categoryColor entry.category)
            , style "flex-shrink" "0"
            ]
            []
        , span [ style "font-size" "20px", style "flex-shrink" "0" ] [ text (categoryIcon entry.category) ]
        , div [ style "flex" "1", style "min-width" "0" ]
            [ div
                [ style "font-size" "15px"
                , style "color" "#c8d0c8"
                , style "white-space" "nowrap"
                , style "overflow" "hidden"
                , style "text-overflow" "ellipsis"
                ]
                [ text
                    (if entry.note /= "" then
                        entry.note

                     else if entry.merchant /= "" then
                        entry.merchant

                     else
                        categoryLabel entry.category
                    )
                ]
            , if entry.merchant /= "" && entry.note /= "" then
                div [ style "font-size" "12px", style "color" "#4a5a50" ] [ text entry.merchant ]

              else
                text ""
            ]
        , span
            [ style "font-family" "monospace"
            , style "font-size" "17px"
            , style "color" "#c8d0c8"
            , style "flex-shrink" "0"
            ]
            [ text (formatAmount entry.amount) ]
        , button
            [ onClick (DeleteEntry entry)
            , style "background" "none"
            , style "border" "none"
            , style "color" "#e85030"
            , style "font-size" "18px"
            , style "cursor" "pointer"
            , style "padding" "4px 8px"
            , style "flex-shrink" "0"
            , style "min-width" "44px"
            , style "min-height" "44px"
            , style "display" "flex"
            , style "align-items" "center"
            , style "justify-content" "center"
            ]
            [ text "✕" ]
        ]


viewSkeleton : Html Msg
viewSkeleton =
    div []
        (List.repeat 5
            (div
                [ style "background" "#161918"
                , style "border-radius" "8px"
                , style "padding" "18px 16px"
                , style "margin-bottom" "8px"
                , style "display" "flex"
                , style "gap" "12px"
                ]
                [ div [ style "width" "10px", style "height" "10px", style "border-radius" "50%", style "background" "#2a3230" ] []
                , div [ style "flex" "1", style "height" "16px", style "background" "#2a3230", style "border-radius" "4px" ] []
                , div [ style "width" "60px", style "height" "16px", style "background" "#2a3230", style "border-radius" "4px" ] []
                ]
            )
        )



-- STATS TAB


viewStatsTab : Model -> Html Msg
viewStatsTab model =
    let
        entries =
            model.entries

        total =
            List.sum (List.map .amount entries)

        numDays =
            List.length (uniqueDates entries)

        numEntries =
            List.length entries

        avgPerDay =
            if numDays > 0 then
                total / toFloat numDays

            else
                0

        avgPerEntry =
            if numEntries > 0 then
                total / toFloat numEntries

            else
                0

        median =
            medianAmount entries

        topCat =
            topCategory entries

        bigDay =
            biggestDay entries

        top5 =
            entries
                |> List.sortBy (\e -> negate e.amount)
                |> List.take 5
    in
    div [ style "padding" "20px" ]
        [ h2 [ sectionHead ] [ text "STATS" ]
        , div
            [ style "display" "grid"
            , style "grid-template-columns" "1fr 1fr"
            , style "gap" "12px"
            , style "margin-bottom" "24px"
            ]
            [ statCard "TOTAL SPENT" (formatAmount total)
            , statCard "ENTRIES" (String.fromInt numEntries)
            , statCard "DAYS ON ROAD" (String.fromInt numDays)
            , statCard "AVG / DAY" (formatAmount avgPerDay)
            , statCard "AVG / ENTRY" (formatAmount avgPerEntry)
            , statCard "MEDIAN" (formatAmount median)
            , statCard "TOP CATEGORY"
                (topCat
                    |> Maybe.map (\c -> categoryIcon c ++ " " ++ categoryLabel c)
                    |> Maybe.withDefault "—"
                )
            , statCard "BIGGEST DAY"
                (bigDay
                    |> Maybe.map (\( _, t ) -> formatAmount t)
                    |> Maybe.withDefault "—"
                )
            ]
        , if List.isEmpty entries then
            text ""

          else
            div
                [ style "background" "#161918"
                , style "border-radius" "10px"
                , style "padding" "20px"
                , style "margin-bottom" "16px"
                ]
                [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "8px" ]
                    [ text "BY CATEGORY" ]
                , viewCategoryChart entries
                ]
        , if numDays > 1 then
            div
                [ style "background" "#161918"
                , style "border-radius" "10px"
                , style "padding" "20px"
                , style "margin-bottom" "16px"
                ]
                [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "8px" ]
                    [ text "DAILY SPENDING" ]
                , viewDailyChart entries
                ]

          else
            text ""
        , if List.isEmpty top5 then
            text ""

          else
            div
                [ style "background" "#161918"
                , style "border-radius" "10px"
                , style "padding" "20px"
                ]
                [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "12px" ]
                    [ text "TOP 5 LARGEST" ]
                , div []
                    (List.indexedMap
                        (\i entry ->
                            div
                                [ style "display" "flex"
                                , style "align-items" "center"
                                , style "gap" "12px"
                                , style "padding" "10px 0"
                                , style "border-bottom" (if i < List.length top5 - 1 then "1px solid #2a3230" else "none")
                                ]
                                [ span [ style "color" "#4a5a50", style "font-family" "monospace", style "width" "20px" ]
                                    [ text (String.fromInt (i + 1) ++ ".") ]
                                , span [ style "font-size" "18px" ] [ text (categoryIcon entry.category) ]
                                , div [ style "flex" "1" ]
                                    [ div [ style "font-size" "14px" ] [ text (if entry.note /= "" then entry.note else categoryLabel entry.category) ]
                                    , div [ style "font-size" "11px", style "color" "#7a8a80" ] [ text entry.date ]
                                    ]
                                , span [ style "font-family" "monospace", style "color" "#e8a020", style "font-size" "16px" ]
                                    [ text (formatAmount entry.amount) ]
                                ]
                        )
                        top5
                    )
                ]
        ]


statCard : String -> String -> Html Msg
statCard label_ value =
    div
        [ style "background" "#161918"
        , style "border-radius" "10px"
        , style "padding" "16px"
        ]
        [ div [ style "font-size" "11px", style "letter-spacing" "0.1em", style "color" "#7a8a80", style "margin-bottom" "6px" ]
            [ text label_ ]
        , div [ style "font-size" "22px", style "font-family" "monospace", style "color" "#e8a020" ]
            [ text value ]
        ]


viewCategoryChart : List Entry -> Html Msg
viewCategoryChart entries =
    let
        rows =
            allCategories
                |> List.map
                    (\cat ->
                        { color = categoryColor cat
                        , label = categoryLabel cat
                        , total =
                            entries
                                |> List.filter (\e -> e.category == cat)
                                |> List.map .amount
                                |> List.sum
                        }
                    )
    in
    C.chart
        [ CA.height 140
        , CA.margin { top = 10, bottom = 28, left = 0, right = 0 }
        ]
        [ C.bars []
            [ C.bar .total []
                |> C.variation (\_ d -> [ CA.color d.color ])
            ]
            rows
        , C.binLabels .label [ CA.moveDown 16, CA.color "#7a8a80", CA.fontSize 9 ]
        ]


viewDailyChart : List Entry -> Html Msg
viewDailyChart entries =
    let
        days =
            uniqueDates entries
                |> List.reverse
                |> List.map
                    (\date ->
                        { date = String.slice 5 10 date
                        , total =
                            entries
                                |> List.filter (\e -> e.date == date)
                                |> List.map .amount
                                |> List.sum
                        }
                    )
    in
    C.chart
        [ CA.height 140
        , CA.margin { top = 10, bottom = 28, left = 0, right = 0 }
        ]
        [ C.bars []
            [ C.bar .total [ CA.color "#e8a020" ] ]
            days
        , C.binLabels .date [ CA.moveDown 16, CA.color "#7a8a80", CA.fontSize 8 ]
        ]



-- SETTINGS TAB


viewSettingsTab : Model -> Html Msg
viewSettingsTab model =
    div [ style "padding" "24px 20px" ]
        [ h2 [ sectionHead ] [ text "SETTINGS" ]
        , formField "GOOGLE CLIENT ID"
            (input
                [ type_ "text"
                , value model.googleClientId
                , onInput GoogleClientIdChanged
                , placeholder "123456789-abc...apps.googleusercontent.com"
                , textInputStyle
                ]
                []
            )
        , formField "GOOGLE SHEET ID"
            (input
                [ type_ "text"
                , value model.sheetId
                , onInput SheetIdChanged
                , placeholder "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms"
                , textInputStyle
                ]
                []
            )
        , formField "ANTHROPIC API KEY"
            (input
                [ type_ "password"
                , value model.anthropicKey
                , onInput ApiKeyChanged
                , placeholder "sk-ant-..."
                , textInputStyle
                ]
                []
            )
        , formField "TRIP START DATE"
            (input
                [ type_ "date"
                , value model.tripStart
                , onInput TripStartChanged
                , textInputStyle
                ]
                []
            )
        , case model.oauthToken of
            Just _ ->
                div [ style "margin-top" "32px" ]
                    [ button
                        [ onClick SignOutClicked
                        , style "width" "100%"
                        , style "background" "none"
                        , style "border" "1px solid #e85030"
                        , style "color" "#e85030"
                        , style "border-radius" "8px"
                        , style "padding" "14px"
                        , style "font-size" "15px"
                        , style "cursor" "pointer"
                        ]
                        [ text "SIGN OUT" ]
                    ]

            Nothing ->
                text ""
        ]



-- SHARED VIEW HELPERS


viewErrorBanner : Model -> Html Msg
viewErrorBanner model =
    case model.error of
        Nothing ->
            text ""

        Just err ->
            div
                [ style "background" "#2a1510"
                , style "border-left" "4px solid #e85030"
                , style "color" "#e8a020"
                , style "padding" "12px 16px"
                , style "margin" "0 20px 16px"
                , style "border-radius" "0 6px 6px 0"
                , style "font-size" "14px"
                , style "display" "flex"
                , style "justify-content" "space-between"
                , style "align-items" "center"
                ]
                [ text err
                , button
                    [ onClick DismissError
                    , style "background" "none"
                    , style "border" "none"
                    , style "color" "#e85030"
                    , style "cursor" "pointer"
                    , style "font-size" "18px"
                    , style "padding" "0 0 0 12px"
                    ]
                    [ text "✕" ]
                ]


formField : String -> Html Msg -> Html Msg
formField label_ input_ =
    div [ style "margin-bottom" "20px" ]
        [ div
            [ style "font-size" "11px"
            , style "letter-spacing" "0.1em"
            , style "color" "#7a8a80"
            , style "margin-bottom" "8px"
            ]
            [ text label_ ]
        , input_
        ]


sectionHead : Attribute Msg
sectionHead =
    style "font-size" "13px"


textInputStyle : Attribute Msg
textInputStyle =
    style "width" "100%"



-- MAIN


main : Program D.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> gotNewToken GotOAuthToken
        }
