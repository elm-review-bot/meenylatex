module Internal.Accumulator exposing (parse, render, renderNew)


import Internal.LatexState
    exposing
        ( Counters
        , CrossReferences
        , LatexState
        )
import Internal.MathMacro
import Internal.Parser as Parser exposing (LatexExpression(..), macro)
import Internal.StateReducerHelpers as ReducerHelper


{-| Given an initial state and list of inputs of type a,
produce a list of outputs of type b and a new state
-}
type alias Accumulator state a b =
    state -> List a -> ( state, List b )


type alias Reducer a b =
    a -> b -> b


{-| parse: Using a given LatexState, take a list of strings,
i.e., paragraphs, and compute a tuple consisting of the parsed
paragraphs and ad updated LatexState.

parse : LatexState -> List String -> ( List (List LatexExpression), LatexState )

-}
parse :
    LatexState
    -> List String
    -> ( LatexState, List ( String, List LatexExpression ) )
parse latexState paragraphs =
    paragraphs
        |> List.foldl parseReducer ( latexState, [] )


parseReducer :
    String
    -> ( LatexState, List ( String, List LatexExpression ) )
    -> ( LatexState, List ( String, List LatexExpression ) )
parseReducer inputString ( latexState, inputList ) =
    let
        parsedInput =
            ( inputString, Parser.parse inputString )

        newLatexState =
            latexStateReducer (Tuple.second parsedInput) latexState
    in
    ( newLatexState, inputList ++ [ parsedInput ] )


{-| render: Using a given LatexState, take a list of (List LatexExpressions)
and compute a tuple consisting of a new list of (List LatexExpressins) and an updated
LatexSttate.

render : LatexState -> List (List LatexExpression) -> ( List String, LatexState )

NOTE: render renderer is an Accumulator

-}
render :
    (LatexState -> List LatexExpression -> a)
    -> LatexState
    -> List ( String, List LatexExpression )
    -> ( LatexState, List a )
render renderer latexState paragraphs =
    paragraphs
        |> List.foldl (renderReducer renderer) ( latexState, [] )


renderNew :
    (LatexState -> List ( String, List LatexExpression ) -> a)
    -> LatexState
    -> List ( String, List LatexExpression )
    -> ( LatexState, List a )
renderNew renderer latexState paragraphs =
    paragraphs
        |> List.foldl (renderReducerNew renderer) ( latexState, [] )


renderReducerNew :
    (LatexState -> List ( String, List LatexExpression ) -> a)
    -> ( String, List LatexExpression )
    -> ( LatexState, List a )
    -> ( LatexState, List a )
renderReducerNew renderer listStringAndLatexExpression ( state, inputList ) =
    let
        newState =
            latexStateReducer (Tuple.second listStringAndLatexExpression) state

        renderedInput =
            renderer newState [ listStringAndLatexExpression ]
    in
    ( newState, inputList ++ [ renderedInput ] )



--render2 :
--    (LatexState -> List LatexExpression -> a)
--    -> LatexState
--    -> List ( String, List LatexExpression )
--    -> ( LatexState, List a )
--render2 renderer latexState paragraphs =
--    paragraphs
--        |> List.foldl (renderReducer renderer) ( latexState, [] )


renderReducer :
    (LatexState -> List LatexExpression -> a)
    -> ( String, List LatexExpression )
    -> ( LatexState, List a )
    -> ( LatexState, List a )
renderReducer renderer listStringAndLatexExpression ( state, inputList ) =
    let
        newState =
            latexStateReducer (Tuple.second listStringAndLatexExpression) state

        renderedInput =
            renderer newState (Tuple.second listStringAndLatexExpression)
    in
    ( newState, inputList ++ [ renderedInput ] )



{-

   > z = LatexList [Macro "title" [] [LatexList [LXString "foo"]],InlineMath ("x^2 = 1"),LXString (", "),Macro "strong" [] [LatexList [LXString "bar"]]]
   LatexList [Macro "title" [] [LatexList [LXString "foo"]],InlineMath ("x^2 = 1"),LXString (", "),Macro "strong" [] [LatexList [LXString "bar"]]]
       : LatexExpression

   > latexStateReducerAux z emptyLatexState
   { counters = Dict.fromList [("eqno",0),("s1",0),("s2",0),("s3",0),("tno",0)], crossReferences = Dict.fromList [], dictionary = Dict.fromList [("title","foo")], macroDictionary = Dict.fromList [], tableOfContents = [] }

-}


latexStateReducer : List LatexExpression -> LatexState -> LatexState
latexStateReducer list state =
    List.foldr latexStateReducerAux state list


latexStateReducerAux : LatexExpression -> LatexState -> LatexState
latexStateReducerAux lexpr state =
    case lexpr of
        Macro name optionalArgs args ->
            macroReducer name optionalArgs args state

        SMacro name optionalArgs args latexExpression ->
            smacroReducer name optionalArgs args latexExpression state

        NewCommand name nArgs body ->
            ReducerHelper.setMacroDefinition name body state

        Environment name optonalArgs body ->
            envReducer name optonalArgs body state

        LatexList list ->
            List.foldr latexStateReducerAux state list

        _ ->
            state


envReducer : String -> List LatexExpression -> LatexExpression -> LatexState -> LatexState
envReducer name optonalArgs body state =
    if List.member name theoremWords then
        ReducerHelper.setTheoremNumber body state

    else
        case name of
            "equation" ->
                ReducerHelper.setEquationNumber body state

            "align" ->
                ReducerHelper.setEquationNumber body state

            "mathmacro" ->
                case body of
                    LXString str ->
                        let
                            mathDict =
                                Internal.MathMacro.makeMacroDict (String.trim str)
                        in
                        { state | mathMacroDictionary = mathDict }

                    _ ->
                        state

            "textmacro" ->
                case body of
                    LXString str ->
                        ReducerHelper.setDictionary str state

                    _ ->
                        state

            _ ->
                state



{-

   > env3
   LatexList [Macro "label" [] [LatexList [LXString "foo"]],LXString ("ho  ho  ho ")]
       : LatexExpression

   > latexStateReducerAux env2 emptyLatexState
   { counters = Dict.fromList [("eqno",0),("s1",0),("s2",0),("s3",0),("tno",1)]
   , crossReferences = Dict.fromList [("foo","0.1")], dictionary = Dict.fromList []
   , macroDictionary = Dict.fromList [], tableOfContents = [] }

-}


theoremWords =
    [ "theorem", "proposition", "corollary", "lemma", "definition", "problem" ]


dictionaryWords =
    [ "title", "author", "date", "email", "revision", "host", "setclient", "setdocid" ]


macroReducer : String -> List LatexExpression -> List LatexExpression -> LatexState -> LatexState
macroReducer name optionalArgs args state =
    if List.member name dictionaryWords then
        ReducerHelper.setDictionaryItemForMacro name args state

    else
        case name of
            "section" ->
                ReducerHelper.updateSectionNumber args state

            "subsection" ->
                ReducerHelper.updateSubsectionNumber args state

            "subsubsection" ->
                ReducerHelper.updateSubsubsectionNumber args state

            "setcounter" ->
                ReducerHelper.setSectionCounters args state

            _ ->
                state


smacroReducer : String -> List LatexExpression -> List LatexExpression -> LatexExpression -> LatexState -> LatexState
smacroReducer name optionalArgs args latexExpression state =
    case name of
        "bibitem" ->
            ReducerHelper.setBibItemXRef optionalArgs args state

        _ ->
            state
