module ReviewConfig exposing (config)

{-| Do not rename the ReviewConfig module or the config function, because
`elm-review` will look for these.
-}

import NoExposingEverything
import NoImportingEverything
import NoMissingTypeAnnotation
import NoMissingTypeExpose
import NoUnused.CustomTypeConstructorArgs
import NoUnused.CustomTypeConstructors
import NoUnused.Dependencies
import NoUnused.Exports
import NoUnused.Modules
import NoUnused.Parameters
import NoUnused.Patterns
import NoUnused.Variables
import NoWildcardOnUpdateFunctions
import Review.Rule as Rule exposing (Rule)
import Simplify


config : List Rule
config =
    List.map
        (Rule.ignoreErrorsForDirectories [ "vendor/", "tests/" ])
        [ NoExposingEverything.rule
        , NoImportingEverything.rule []
        , NoMissingTypeAnnotation.rule
        , NoMissingTypeExpose.rule
        , NoUnused.CustomTypeConstructorArgs.rule
        , NoUnused.CustomTypeConstructors.rule []
        , NoUnused.Dependencies.rule

        -- Data.Stats and Data.SubscriptionStatus expose pure helpers that are
        -- used only internally (own decoders / bin builders) but must stay
        -- exposed so elm-verify-examples can run their `-->` doc examples.
        -- NoUnused.Exports can't see the generated tests (tests/ is ignored),
        -- so it flags them; suppress the rule for just those two modules.
        , NoUnused.Exports.rule
            |> Rule.ignoreErrorsForFiles
                [ "src/Data/Stats.elm"
                , "src/Data/SubscriptionStatus.elm"
                ]
        , NoUnused.Modules.rule
        , NoUnused.Parameters.rule
        , NoUnused.Patterns.rule
        , NoUnused.Variables.rule
        , NoWildcardOnUpdateFunctions.rule
        , Simplify.rule Simplify.defaults
        ]
