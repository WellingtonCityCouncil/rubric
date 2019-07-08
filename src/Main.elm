port module Main exposing (Model)

import Browser
import Browser.Navigation as Nav
import ElmEscapeHtml exposing (escape, unescape)
import FeatherIcons
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Json.Decode as Decode exposing (Decoder, float, int, nullable, string)
import Json.Decode.Pipeline exposing (hardcoded, optional, required)
import Json.Encode as Encode
import List.Extra as ListX
import Process
import Task



-- MODEL


type alias Model =
    { activities : List Activity
    , selectedActivity : Maybe Activity
    , selectedProperty : Maybe Property
    , standards : List Standard
    , status : Status
    , errors : List String
    }


type alias Activity =
    String


type alias Property =
    { fullAddress : String
    , streetNumber : String
    , streetName : String
    , suburb : String
    , postCode : String
    , title : String
    , valuationId : String
    , valuationWufi : Int
    , dpZone : String
    , specialResidentialArea : String
    }


type alias Standard =
    { key : String
    , description : String
    , name : String
    , questions : List Question
    , section : String
    , status : String
    }


type alias Question =
    { key : String
    , input : Input
    , unit : String
    , value : String
    }


type Input
    = Text String
    | Number String
    | Multichoice String (List String)
    | File String


type Status
    = Permitted
    | Controlled
    | DiscretionaryRestricted
    | DiscretionaryUnrestricted
    | NonCompliant
    | Unknown


type Msg
    = NoOp
    | AddError String
    | ExpireError
    | SelectActivity Activity
    | SelectMapProperty Decode.Value
    | ReceiveStandards Decode.Value
    | GenerateStandards


init : List String -> ( Model, Cmd Msg )
init flags =
    let
        model =
            { activities = flags
            , selectedActivity = Nothing
            , selectedProperty = Nothing
            , standards = []
            , errors = []
            , status = Unknown
            }
    in
    ( model, Cmd.none )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        AddError e ->
            ( { model | errors = model.errors ++ [ e ] }, delay 5000 ExpireError )

        ExpireError ->
            ( { model | errors = List.drop 1 model.errors }, Cmd.none )

        SelectActivity activity ->
            ( { model | selectedActivity = Just activity }, Cmd.none )

        SelectMapProperty propertyValue ->
            case Decode.decodeValue decodeProperty propertyValue of
                Ok p ->
                    ( { model | selectedProperty = Just p }, Cmd.none )

                Err err ->
                    let
                        debug =
                            Debug.log "Error decoding section: " <|
                                Decode.errorToString err
                    in
                    ( model, addError "Oops! An error has occurred. Check the console for more details." )

        ReceiveStandards val ->
            case Decode.decodeValue decodeStandards val of
                Ok s ->
                    ( { model | standards = s }, Cmd.none )

                Err err ->
                    let
                        debug =
                            Debug.log "Error decoding section: " <|
                                Decode.errorToString err
                    in
                    ( model, addError "Oops! An error has occurred. Check the console for more details." )

        GenerateStandards ->
            case ( model.selectedActivity, model.selectedProperty ) of
                ( Just a, Just p ) ->
                    ( model, generateStandards <| encodeInit a p )

                ( Nothing, Just p ) ->
                    ( model, addError "You need to select an activity first!" )

                ( Just a, Nothing ) ->
                    ( model, addError "You need to select a property first!" )

                ( Nothing, Nothing ) ->
                    ( model, addError "You need to select a property and an activity first!" )



-- INTEROP


port selectMapProperty : (Decode.Value -> msg) -> Sub msg


port generateStandards : Encode.Value -> Cmd msg


port receiveStandards : (Decode.Value -> msg) -> Sub msg


encodeInit : Activity -> Property -> Encode.Value
encodeInit a p =
    Encode.object
        [ ( "activity", Encode.string a )
        , ( "zone", Encode.string p.dpZone )
        , ( "address", Encode.string p.fullAddress )
        , ( "area_specific_layers", Encode.string p.specialResidentialArea )
        , ( "valuation_wufi", Encode.int p.valuationWufi )
        ]


decodeProperty : Decode.Decoder Property
decodeProperty =
    Decode.succeed Property
        |> required "fullAddress" string
        |> required "streetNumber" string
        |> required "streetName" string
        |> required "suburb" string
        |> required "postCode" string
        |> optional "title" string "No Associated Title"
        |> required "valuationId" string
        |> required "valuationWufi" int
        |> required "dpZone" string
        |> required "specialResidentialArea" string


decodeStandards : Decode.Decoder (List Standard)
decodeStandards =
    Decode.list decodeStandard


decodeStandard : Decode.Decoder Standard
decodeStandard =
    Decode.succeed Standard
        |> required "key" string
        |> required "description" string
        |> required "name" string
        |> required "questions" (Decode.list decodeQuestion)
        |> required "section" string
        |> optional "activityStatus" string "Unknown"


decodeQuestion : Decode.Decoder Question
decodeQuestion =
    Decode.succeed Question
        |> required "key" string
        |> required "input" decodeInput
        |> required "unit" string
        |> hardcoded ""


decodeInput : Decode.Decoder Input
decodeInput =
    Decode.field "format" Decode.string
        |> Decode.andThen matchInput


matchInput : String -> Decode.Decoder Input
matchInput format =
    case format of
        "text" ->
            Decode.succeed Text
                |> required "prompt" string

        "number" ->
            Decode.succeed Number
                |> required "prompt" string

        "multichoice" ->
            Decode.succeed Multichoice
                |> required "prompt" string
                |> required "options" (Decode.list string)

        "file" ->
            Decode.succeed File
                |> required "prompt" string

        _ ->
            Decode.fail ("Invalid format: " ++ format)



-- VIEW


view : Model -> Html Msg
view model =
    let
        errorMessage e =
            div [ class "error-message" ] [ text e ]
    in
    div [ id "container" ]
        [ div [ class "errors" ] (List.map errorMessage model.errors)
        , renderSidebar model.standards model.status
        , renderContent model
        ]


renderSidebar : List Standard -> Status -> Html msg
renderSidebar standards status =
    let
        sectionButton i s =
            a [ class "standard", href <| "#standard-" ++ String.fromInt i ]
                [ text s.name ]

        statusToString =
            case status of
                Permitted ->
                    "Permitted"

                Controlled ->
                    "Controlled"

                DiscretionaryRestricted ->
                    "Discretionary Restricted"

                DiscretionaryUnrestricted ->
                    "Discretionary Unrestricted"

                NonCompliant ->
                    "Non-compliant"

                Unknown ->
                    "Status unknown: You'll need to provide more information."

        statusBox =
            div [ class "status" ] [ text statusToString ]
    in
    div [ id "sidebar" ]
        [ h1 [] [ text "RuBRIC" ]
        , h3 [ class "subtitle" ] [ text "A Proof of Concept" ]
        , div [ class "standards" ] <|
            List.indexedMap sectionButton standards
        , statusBox
        ]


renderContent : Model -> Html Msg
renderContent model =
    let
        activitySelect =
            div [ class "question" ]
                [ label [ for "activity-select" ]
                    [ text "What do you want to do?" ]
                , select [ id "activity-select", onInput SelectActivity ] <|
                    option [ hidden True, disabled True, selected True ] [ text "Select an activity..." ]
                        :: List.map (\a -> option [ value a ] [ text a ]) model.activities
                ]

        propertySelect =
            let
                propertyTable =
                    case model.selectedProperty of
                        Just p ->
                            input [ class "property-input", readonly True, value p.fullAddress ] []

                        Nothing ->
                            input [ class "property-input", readonly True, placeholder "Please use the map to select a property..." ] []
            in
            div [ class "question" ]
                [ label [ for "property-select" ]
                    [ text "What is the address of the property?" ]
                , div [ id "map" ] []
                , propertyTable
                ]

        displayStandards i s =
            details [ class "standards", id <| "standards-" ++ String.fromInt i, attribute "open" "true" ]
                [ summary [] [ text s.name ]
                , div [ class "questions" ] <|
                    List.map displayQuestion s.questions
                ]

        displayQuestion q =
            case q.input of
                Text p ->
                    div [ class "question" ]
                        [ label [ for q.key ] [ text <| unescape p ]
                        , input [ id q.key, type_ "text" ] []
                        ]

                Number p ->
                    div [ class "question" ]
                        [ label [ for q.key ] [ text <| unescape p ]
                        , input [ id q.key, type_ "number" ] []
                        ]

                Multichoice p ops ->
                    div [ class "question" ]
                        [ label [ for q.key ] [ text <| unescape p ]
                        , input [ id q.key, type_ "text" ] []
                        ]

                File p ->
                    div [ class "question" ]
                        [ label [ for q.key ] [ text <| unescape p ]
                        , input [ id q.key, type_ "file" ] []
                        ]

        submitButton =
            if List.isEmpty model.standards then
                div [ class "button", onClick GenerateStandards ]
                    [ text "Generate Standards" ]

            else
                div [] []
    in
    div [ id "content" ]
        [ h1 [] [ text "Submit a Building & Structure Consent Application" ]
        , Html.form [] <|
            [ activitySelect, propertySelect ]
                ++ List.indexedMap displayStandards model.standards
                ++ [ submitButton ]
        ]



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch [ selectMapProperty SelectMapProperty, receiveStandards ReceiveStandards ]



-- MAIN


main : Program (List String) Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }



-- HELPERS


addError : String -> Cmd Msg
addError s =
    AddError s
        |> Task.succeed
        |> Task.perform identity


delay : Float -> msg -> Cmd msg
delay time msg =
    Process.sleep time
        |> Task.perform (\_ -> msg)
