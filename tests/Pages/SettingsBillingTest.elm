module Pages.SettingsBillingTest exposing (suite)

{-| Render `Pages.Settings.viewPlanSection` for each tier and assert
that the buttons + chip + countdown copy match the spec from #21.

These are pure view tests over the small `PlanProps` projection — the
section's update logic lives in `Main.updateAuth` and is exercised
end-to-end by the Playwright suite. What we test here is the much
narrower "did the right Tailwind chrome and the right
`BillingCheckoutClicked` / `BillingPortalClicked` payloads end up on
the DOM."

-}

import Data.SubscriptionStatus as SubscriptionStatus
import Data.Tier exposing (Tier(..))
import Expect
import Http
import Http.Billing
import Pages.Settings
import RemoteData
import Test exposing (Test, describe, test)
import Test.Html.Event
import Test.Html.Query
import Test.Html.Selector
import Types exposing (AuthMsg_(..), Msg(..))


suite : Test
suite =
    describe "Pages.Settings.viewPlanSection"
        [ describe "Tern"
            [ test "renders three upgrade CTAs" <|
                \() ->
                    propsFor { tier = Tern, trailblazerStatus = RemoteData.Success { available = 412, total = 500 } }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.has
                            [ Test.Html.Selector.text "Osprey — $2.99 / mo"
                            , Test.Html.Selector.text "Osprey yearly — $24 / yr (save $12)"
                            , Test.Html.Selector.text "Become a Trailblazer — $79 (412 of 500 left)"
                            ]
            , test "Trailblazer button is disabled with Sold out copy when available == 0" <|
                \() ->
                    propsFor { tier = Tern, trailblazerStatus = RemoteData.Success { available = 0, total = 500 } }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.has
                            [ Test.Html.Selector.text "Trailblazer — Sold out" ]
            , test "Trailblazer button shows Loading… while status is in flight (Nothing)" <|
                \() ->
                    propsFor { tier = Tern, trailblazerStatus = RemoteData.NotAsked }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.has
                            [ Test.Html.Selector.text "Loading…" ]
            , test "clicking the monthly button fires BillingCheckoutClicked osprey_monthly" <|
                \() ->
                    propsFor { tier = Tern, trailblazerStatus = RemoteData.Success { available = 412, total = 500 } }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.findAll
                            [ Test.Html.Selector.tag "button"
                            , Test.Html.Selector.containing
                                [ Test.Html.Selector.text "Osprey — $2.99 / mo" ]
                            ]
                        |> Test.Html.Query.first
                        |> Test.Html.Event.simulate Test.Html.Event.click
                        |> Test.Html.Event.expect (AuthMsg (BillingCheckoutClicked "osprey_monthly"))
            , test "clicking the yearly button fires BillingCheckoutClicked osprey_yearly" <|
                \() ->
                    propsFor { tier = Tern, trailblazerStatus = RemoteData.Success { available = 412, total = 500 } }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.findAll
                            [ Test.Html.Selector.tag "button"
                            , Test.Html.Selector.containing
                                [ Test.Html.Selector.text "Osprey yearly" ]
                            ]
                        |> Test.Html.Query.first
                        |> Test.Html.Event.simulate Test.Html.Event.click
                        |> Test.Html.Event.expect (AuthMsg (BillingCheckoutClicked "osprey_yearly"))
            , test "clicking the Trailblazer button fires BillingCheckoutClicked trailblazer" <|
                \() ->
                    propsFor { tier = Tern, trailblazerStatus = RemoteData.Success { available = 412, total = 500 } }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.findAll
                            [ Test.Html.Selector.tag "button"
                            , Test.Html.Selector.containing
                                [ Test.Html.Selector.text "Become a Trailblazer" ]
                            ]
                        |> Test.Html.Query.first
                        |> Test.Html.Event.simulate Test.Html.Event.click
                        |> Test.Html.Event.expect (AuthMsg (BillingCheckoutClicked "trailblazer"))
            , test "billingCheckout SoldOut failure renders the error chip" <|
                \() ->
                    let
                        props =
                            propsFor { tier = Tern, trailblazerStatus = RemoteData.Success { available = 0, total = 500 } }
                    in
                    { props
                        | billingCheckout = RemoteData.Failure Http.Billing.CheckoutSoldOut
                    }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.has
                            [ Test.Html.Selector.text "Sorry, the last Trailblazer slot just sold out." ]
            ]
        , describe "Osprey"
            [ test "renders the Manage billing button" <|
                \() ->
                    propsFor { tier = Osprey, trailblazerStatus = RemoteData.Success { available = 412, total = 500 } }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.has
                            [ Test.Html.Selector.text "Manage billing" ]
            , test "doesn't render any upgrade CTAs" <|
                \() ->
                    propsFor { tier = Osprey, trailblazerStatus = RemoteData.Success { available = 412, total = 500 } }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.hasNot
                            [ Test.Html.Selector.text "Osprey — $2.99 / mo" ]
            , test "clicking Manage billing fires BillingPortalClicked" <|
                \() ->
                    propsFor { tier = Osprey, trailblazerStatus = RemoteData.Success { available = 412, total = 500 } }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.find
                            [ Test.Html.Selector.tag "button"
                            , Test.Html.Selector.containing
                                [ Test.Html.Selector.text "Manage billing" ]
                            ]
                        |> Test.Html.Event.simulate Test.Html.Event.click
                        |> Test.Html.Event.expect (AuthMsg BillingPortalClicked)
            , test "renders the PastDue chip when subscriptionStatus is PastDue" <|
                \() ->
                    let
                        props =
                            propsFor { tier = Osprey, trailblazerStatus = RemoteData.Success { available = 412, total = 500 } }
                    in
                    { props | subscriptionStatus = Just SubscriptionStatus.PastDue }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.has [ Test.Html.Selector.text "Past due" ]
            , test "does not render an Active chip when subscriptionStatus is Active" <|
                \() ->
                    let
                        props =
                            propsFor { tier = Osprey, trailblazerStatus = RemoteData.Success { available = 412, total = 500 } }
                    in
                    { props | subscriptionStatus = Just SubscriptionStatus.Active }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.hasNot [ Test.Html.Selector.text "Active" ]
            ]
        , describe "Trailblazer"
            [ test "renders the badge with the user's number" <|
                \() ->
                    let
                        props =
                            propsFor { tier = Trailblazer, trailblazerStatus = RemoteData.Success { available = 0, total = 500 } }
                    in
                    { props | trailblazerNumber = Just 17 }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.has
                            [ Test.Html.Selector.text "Trailblazer #17 (of 500)" ]
            , test "renders the View receipts / update card button" <|
                \() ->
                    propsFor { tier = Trailblazer, trailblazerStatus = RemoteData.Success { available = 0, total = 500 } }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.has
                            [ Test.Html.Selector.text "View receipts / update card" ]
            , test "clicking View receipts fires BillingPortalClicked" <|
                \() ->
                    propsFor { tier = Trailblazer, trailblazerStatus = RemoteData.Success { available = 0, total = 500 } }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.find
                            [ Test.Html.Selector.tag "button"
                            , Test.Html.Selector.containing
                                [ Test.Html.Selector.text "View receipts / update card" ]
                            ]
                        |> Test.Html.Event.simulate Test.Html.Event.click
                        |> Test.Html.Event.expect (AuthMsg BillingPortalClicked)
            ]
        , describe "billingCheckout Loading"
            [ test "Tern upgrade buttons render as disabled while a checkout is in flight" <|
                \() ->
                    let
                        props =
                            propsFor { tier = Tern, trailblazerStatus = RemoteData.Success { available = 412, total = 500 } }
                    in
                    { props | billingCheckout = RemoteData.Loading }
                        |> Pages.Settings.viewPlanSection
                        |> Test.Html.Query.fromHtml
                        |> Test.Html.Query.findAll
                            [ Test.Html.Selector.tag "button"
                            , Test.Html.Selector.disabled True
                            ]
                        |> Test.Html.Query.count
                            (\n ->
                                if n >= 3 then
                                    Expect.pass

                                else
                                    Expect.fail
                                        ("expected ≥3 disabled buttons; got " ++ String.fromInt n)
                            )
            ]
        ]


propsFor : { tier : Tier, trailblazerStatus : RemoteData.RemoteData Http.Error Http.Billing.TrailblazerStatus } -> Pages.Settings.PlanProps
propsFor { tier, trailblazerStatus } =
    { billingCheckout = RemoteData.NotAsked
    , billingPortal = RemoteData.NotAsked
    , subscriptionStatus = Nothing
    , tier = tier
    , trailblazerNumber = Nothing
    , trailblazerStatus = trailblazerStatus
    }
