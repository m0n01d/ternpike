module ProgramTestSetupTest exposing (suite)

{-| Reference + smoke test for `avh4/elm-program-test`.

This file is the working template for adding view+update tests against
ternpike pages. It defines a tiny self-contained program (`PaymentForm`)
that uses real `Data.Category` / `Data.PaymentMethod` so the example
isn't pure ceremony, and exercises the program-test patterns we want to
use against `Pages/*` once those pages are refactored to be testable
(extract a `Page` `Model`/`Msg`/`update`/`view` quartet out of the
monolithic `Main.elm`).

If this test breaks, the dependency wiring is wrong. Fix that first
before trying to add real page tests.

-}

import Data.Category as Category exposing (Category)
import Data.PaymentMethod as PaymentMethod exposing (PaymentMethod)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import ProgramTest exposing (ProgramTest)
import Test exposing (Test, describe, test)
import Test.Html.Selector



-- PROGRAM UNDER TEST


type alias Model =
    { amountInput : String
    , method : PaymentMethod
    , saved : List Entry
    , selectedCategory : Category
    }


type alias Entry =
    { amount : String
    , category : Category
    , method : PaymentMethod
    }


type Msg
    = ChangedAmount String
    | PickedCategory Category
    | PickedMethod PaymentMethod
    | SubmittedEntry


init : () -> ( Model, Cmd Msg )
init () =
    ( { amountInput = ""
      , method = PaymentMethod.Cash
      , saved = []
      , selectedCategory = Category.Food
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ChangedAmount value ->
            ( { model | amountInput = value }, Cmd.none )

        PickedCategory cat ->
            ( { model | selectedCategory = cat }, Cmd.none )

        PickedMethod pm ->
            ( { model | method = pm }, Cmd.none )

        SubmittedEntry ->
            if String.isEmpty (String.trim model.amountInput) then
                ( model, Cmd.none )

            else
                ( { model
                    | amountInput = ""
                    , saved =
                        { amount = model.amountInput
                        , category = model.selectedCategory
                        , method = model.method
                        }
                            :: model.saved
                  }
                , Cmd.none
                )


view : Model -> Html Msg
view model =
    Html.div []
        [ Html.label [ Html.Attributes.for "amount" ] [ Html.text "Amount" ]
        , Html.input
            [ Html.Attributes.id "amount"
            , Html.Attributes.value model.amountInput
            , Html.Events.onInput ChangedAmount
            ]
            []
        , Html.div [] (List.map (viewCategoryButton model.selectedCategory) Category.all)
        , Html.div [] (List.map (viewMethodButton model.method) [ PaymentMethod.Cash, PaymentMethod.Credit ])
        , Html.button [ Html.Events.onClick SubmittedEntry ] [ Html.text "Save expense" ]
        , Html.ul [] (List.map viewSavedEntry model.saved)
        ]


viewCategoryButton : Category -> Category -> Html Msg
viewCategoryButton selected cat =
    Html.button
        [ Html.Events.onClick (PickedCategory cat)
        , Html.Attributes.classList [ ( "is-selected", cat == selected ) ]
        ]
        [ Html.text (Category.label cat) ]


viewMethodButton : PaymentMethod -> PaymentMethod -> Html Msg
viewMethodButton selected pm =
    Html.button
        [ Html.Events.onClick (PickedMethod pm)
        , Html.Attributes.classList [ ( "is-selected", pm == selected ) ]
        ]
        [ Html.text (PaymentMethod.label pm) ]


viewSavedEntry : Entry -> Html Msg
viewSavedEntry entry =
    Html.li []
        [ Html.text
            (String.join " · "
                [ entry.amount
                , Category.label entry.category
                , PaymentMethod.label entry.method
                ]
            )
        ]



-- TEST DRIVER


start : ProgramTest Model Msg (Cmd Msg)
start =
    ProgramTest.createElement
        { init = init
        , update = update
        , view = view
        }
        |> ProgramTest.start ()


suite : Test
suite =
    describe "elm-program-test wiring"
        [ test "fillIn + clickButton saves an entry to the list" <|
            \() ->
                start
                    |> ProgramTest.fillIn "amount" "Amount" "12.50"
                    |> ProgramTest.clickButton "Save expense"
                    |> ProgramTest.expectViewHas
                        [ Test.Html.Selector.tag "li"
                        , Test.Html.Selector.text "12.50"
                        , Test.Html.Selector.text "food"
                        , Test.Html.Selector.text "Cash"
                        ]
        , test "picking a category before saving uses that category" <|
            \() ->
                start
                    |> ProgramTest.fillIn "amount" "Amount" "42"
                    |> ProgramTest.clickButton "fuel"
                    |> ProgramTest.clickButton "Credit"
                    |> ProgramTest.clickButton "Save expense"
                    |> ProgramTest.expectViewHas
                        [ Test.Html.Selector.tag "li"
                        , Test.Html.Selector.text "fuel"
                        , Test.Html.Selector.text "Credit"
                        ]
        , test "submitting with a blank amount is a no-op (no <li> rendered)" <|
            \() ->
                start
                    |> ProgramTest.clickButton "Save expense"
                    |> ProgramTest.expectViewHasNot
                        [ Test.Html.Selector.tag "li" ]
        ]
