module UI.Button exposing
    ( danger
    , ghost
    , iconButton
    , primary
    , primaryBusy
    , secondary
    )

import Html exposing (Html)
import Html.Attributes
import Html.Events


danger : { label : String, onClick : msg } -> Html msg
danger { label, onClick } =
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Events.onClick onClick
        , Html.Attributes.class "bg-danger text-parchment font-mono uppercase tracking-widest text-sm px-6 py-3 rounded-lg border-none cursor-pointer"
        ]
        [ Html.text label ]


ghost : { label : String, onClick : msg } -> Html msg
ghost { label, onClick } =
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Events.onClick onClick
        , Html.Attributes.class "bg-transparent border border-tan text-moss font-mono uppercase tracking-widest text-xs px-4 py-2 rounded-lg cursor-pointer hover:text-forest hover:border-moss"
        ]
        [ Html.text label ]


iconButton : { icon : Html msg, onClick : msg, title : String } -> Html msg
iconButton { icon, onClick, title } =
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Events.onClick onClick
        , Html.Attributes.title title
        , Html.Attributes.class "w-9 h-9 flex items-center justify-center rounded-full bg-transparent border border-tan text-moss hover:text-rust hover:border-rust cursor-pointer"
        ]
        [ icon ]


primary : { label : String, onClick : msg } -> Html msg
primary { label, onClick } =
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Events.onClick onClick
        , Html.Attributes.class "bg-rust hover:bg-rust-deep text-parchment font-mono uppercase tracking-widest text-sm px-6 py-3 rounded-lg border-none cursor-pointer"
        ]
        [ Html.text label ]


primaryBusy : { label : String } -> Html msg
primaryBusy { label } =
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Attributes.disabled True
        , Html.Attributes.class "bg-rust/60 text-parchment font-mono uppercase tracking-widest text-sm px-6 py-3 rounded-lg border-none cursor-not-allowed"
        ]
        [ Html.text label ]


secondary : { label : String, onClick : msg } -> Html msg
secondary { label, onClick } =
    Html.button
        [ Html.Attributes.type_ "button"
        , Html.Events.onClick onClick
        , Html.Attributes.class "bg-cream-deep border border-tan text-forest font-mono uppercase tracking-widest text-sm px-6 py-3 rounded-lg cursor-pointer hover:bg-tan"
        ]
        [ Html.text label ]
