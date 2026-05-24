module NoWildcardOnUpdateFunctions exposing (rule)

{-| Forbids wildcard (`_ ->`) patterns in the top-level `case msg of` block of
functions whose names start with `update`.

Wildcard catch-alls in dispatch functions silently swallow renamed or newly-added
Msg constructors. The Elm compiler cannot warn about an unhandled constructor when
a `_ ->` arm already matches it.

    config =
        [ NoWildcardOnUpdateFunctions.rule
        ]

-}

import Elm.Syntax.Declaration as Declaration
import Elm.Syntax.Expression as Expression
import Elm.Syntax.Node as Node exposing (Node)
import Elm.Syntax.Pattern as Pattern
import Review.Rule as Rule exposing (Rule)


{-| Reports `_ ->` catch-all patterns in the outermost `case` of any top-level
function whose name begins with `update`.

    updateFoo msg model =
        case msg of
            DoThing ->
                ...

            _ ->      -- flagged
                ( model, Cmd.none )

-}
rule : Rule
rule =
    Rule.newModuleRuleSchema "NoWildcardOnUpdateFunctions" ()
        |> Rule.withSimpleDeclarationVisitor declarationVisitor
        |> Rule.fromModuleRuleSchema


declarationVisitor : Node Declaration.Declaration -> List (Rule.Error {})
declarationVisitor node =
    case Node.value node of
        Declaration.FunctionDeclaration function ->
            let
                impl : Expression.FunctionImplementation
                impl =
                    Node.value function.declaration

                name : String
                name =
                    Node.value impl.name
            in
            if String.startsWith "update" name then
                checkOutermostCase impl.expression

            else
                []

        _ ->
            []


checkOutermostCase : Node Expression.Expression -> List (Rule.Error {})
checkOutermostCase bodyNode =
    case Node.value bodyNode of
        Expression.CaseExpression caseBlock ->
            List.concatMap (checkCase (Node.value caseBlock.expression)) caseBlock.cases

        Expression.LetExpression letBlock ->
            -- Unwrap a leading let-in; the case may be the result expression.
            checkOutermostCase letBlock.expression

        _ ->
            []


checkCase : Expression.Expression -> Expression.Case -> List (Rule.Error {})
checkCase _ ( patternNode, _ ) =
    case Node.value patternNode of
        Pattern.AllPattern ->
            [ Rule.error
                { message = "Wildcard `_ ->` is not allowed in the top-level case of an update function."
                , details =
                    [ "Catch-all patterns in dispatch functions silently swallow renamed or newly-added Msg constructors."
                    , "Replace this `_ ->` with an explicit branch for every remaining Msg constructor so the Elm compiler can enforce totality."
                    ]
                }
                (Node.range patternNode)
            ]

        _ ->
            []
