module Internal.DifferSimple exposing (..)

{-| This module is used to speed up parsing-rendering by
comparing the old and new lists of paragraphs, noting the changes,
then parsing and rendering the changed paragraphs.


# API

@docs EditRecord, emptyStringRecord, emptyHtmlMsgRecord, isEmpty, init, diff, prefixer, update, simpleDifferentialRender

-}

import Internal.LatexState exposing (LatexState, emptyLatexState)
import Internal.Paragraph as Paragraph
import Internal.Parser exposing (LatexExpression(..))



{- TYPES -}


type alias DiffRecord =
    { commonInitialSegment : List String
    , commonTerminalSegment : List String
    , middleSegmentInSource : List String
    , middleSegmentInTarget : List String
    }


type alias IdListPacket =
    { idList : List String
    , newIdsStart : Maybe Int
    , newIdsEnd : Maybe Int
    }


{-| An EditRecord records a list of (logical) newParagraphs
corresponding to the text to be rendered as well as corresponding
list of rendered paragraphs. We need to reveiw this strucure.
-}
type alias EditRecord =
    { source : String
    , mpreamble : Maybe String
    , paragraphs : List String
    , astList : List ( String, List LatexExpression )
    , idList : List String
    , latexState : LatexState
    }


{-| An empty EditRecord -- like the integer 0 in another context.
-}
emptyEditRecord : EditRecord
emptyEditRecord =
    EditRecord "" Nothing [] [] [] emptyLatexState

addPreamble : String -> Maybe String -> String
addPreamble text mpreamble =
    case mpreamble of
        Nothing -> text
        Just str -> str ++ "\n\n" ++ text

{-| createRecord: Create an edit record by (1)
breaking the text in to paragraphs, (2) applying
the transformer to each string in the resulting
list of strings.
-}
init : (String -> List LatexExpression) -> (String -> a) -> String -> Maybe String -> EditRecord
init parser renderer text mpreamble =
    let
        paragraphs =
            Paragraph.logicalParagraphify (addPreamble text mpreamble)

        n =
            List.length paragraphs

        idList =
            List.range 1 n |> List.map (prefixer 0) |> List.map (\i -> "X." ++ i)

        astList =
            List.map (\p -> ( p, parser p )) paragraphs

        preamble = case mpreamble of
            Nothing -> ""
            Just str -> str
    in
    EditRecord text mpreamble paragraphs astList idList emptyLatexState


{-| An EditRecord is considered to be empyt if its list of parapgraphs
and its list of rendered paraagrahs is empty
-}
isEmpty : EditRecord -> Bool
isEmpty editRecord =
    editRecord.paragraphs == []


{-| The update function takes an EditRecord and a string, the "text",
breaks the text into a list of logical paragraphs, diffs it with the list
of paragraphs held by the EditRecord, uses `differentialRender` to
render the changed paragraphs while copying the unchanged rendered paragraphsto
prodduce an updated list of rendered paragraphs. The 'differentialRender'
accomplishes this using the transformer. The seed is used to produces
a differential idList. This last step is perhaps unnecessary. To investigate.
(This was part of an optimization scheme.)
-}
update : Int -> (String -> List LatexExpression) -> EditRecord -> String -> Maybe String -> EditRecord
update seed parser editRecord text mpreamble =
    let
        newParagraphs = case mpreamble of
            Nothing ->  Paragraph.logicalParagraphify (addPreamble text editRecord.mpreamble )
            Just preamble -> Paragraph.logicalParagraphify (preamble ++ "\n\n" ++ text)

        diffRecord =
            diff editRecord.paragraphs newParagraphs

        astList =
            differentialCompiler parser diffRecord editRecord

        p =
            differentialIdList seed diffRecord editRecord
    in
    EditRecord text editRecord.mpreamble newParagraphs astList p.idList editRecord.latexState


{-| Update the renderedList by applying the transformer only to the
changed source elements.
-}
simpleDifferentialRender : (String -> a) -> DiffRecord -> List a -> List a
simpleDifferentialRender transformer diffRecord renderedList =
    let
        prefixLengh =
            List.length diffRecord.commonInitialSegment

        suffixLength =
            List.length diffRecord.commonTerminalSegment

        renderedPrefix =
            List.take prefixLengh renderedList

        renderedSuffix =
            takeLast suffixLength renderedList
    in
    renderedPrefix ++ List.map transformer diffRecord.middleSegmentInTarget ++ renderedSuffix


{-| Let u and v be two lists of strings. Write them as
u = axb, v = ayb, where a is the greatest common prefix
and b is the greatest common suffix. Return DiffRecord a b x y
-}
diff : List String -> List String -> DiffRecord
diff u v =
    let
        a =
            commonInitialSegment u v

        b_ =
            commonTerminalSegmentAux a u v

        la =
            List.length a

        lb =
            List.length b_

        x =
            u |> List.drop la |> dropLast lb

        y =
            v |> List.drop la |> dropLast lb

        b =
            if la == List.length u then
                []

            else
                b_
    in
    DiffRecord a b x y


commonInitialSegment : List String -> List String -> List String
commonInitialSegment x y =
    if x == [] then
        []

    else if y == [] then
        []

    else
        let
            a =
                List.take 1 x

            b =
                List.take 1 y
        in
        if a == b then
            a ++ commonInitialSegment (List.drop 1 x) (List.drop 1 y)

        else
            []



-- commonTerminalSegment1 : List String -> List String -> List String
-- commonTerminalSegment1 x y =
--     commonInitialSegment (List.reverse x) (List.reverse y) |> List.reverse


commonTerminalSegment : List String -> List String -> List String
commonTerminalSegment x y =
    let
        cis =
            commonInitialSegment x y
    in
    commonTerminalSegmentAux cis x y


commonTerminalSegmentAux : List String -> List String -> List String -> List String
commonTerminalSegmentAux cis x y =
    let
        n =
            List.length cis

        xx =
            List.drop n x |> List.reverse

        yy =
            List.drop n y |> List.reverse
    in
    commonInitialSegment xx yy |> List.reverse


dropLast : Int -> List a -> List a
dropLast k x =
    x |> List.reverse |> List.drop k |> List.reverse


takeLast : Int -> List a -> List a
takeLast k x =
    x |> List.reverse |> List.take k |> List.reverse


{-| The prefixer is used to generate unique id's "p.1", "p.2", etc.
for each paragraph.
-}
prefixer : Int -> Int -> String
prefixer b k =
    "p." ++ String.fromInt b ++ "." ++ String.fromInt k


differentialParser : (String -> List LatexExpression) -> DiffRecord -> EditRecord -> List ( String, List LatexExpression )
differentialParser parser diffRecord editRecord =
    let
        ii =
            List.length diffRecord.commonInitialSegment

        it =
            List.length diffRecord.commonTerminalSegment

        initialSegmentParsed =
            List.take ii editRecord.astList

        terminalSegmentParsed =
            takeLast it editRecord.astList

        middleSegmentParsed =
            List.map (\p -> ( p, parser p )) diffRecord.middleSegmentInTarget
    in
    initialSegmentParsed ++ middleSegmentParsed ++ terminalSegmentParsed


differentialCompiler :
    (String -> List LatexExpression)
    -> DiffRecord
    -> EditRecord
    -> List ( String, List LatexExpression )
differentialCompiler parser diffRecord editRecord =
    let
        ii =
            List.length diffRecord.commonInitialSegment

        it =
            List.length diffRecord.commonTerminalSegment

        initialSegmentParsed =
            List.take ii editRecord.astList

        terminalSegmentParsed =
            takeLast it editRecord.astList

        middleSegmentParsed : List ( String, List LatexExpression )
        middleSegmentParsed =
            List.map (\p -> ( p, parser p )) diffRecord.middleSegmentInTarget
    in
    initialSegmentParsed ++ middleSegmentParsed ++ terminalSegmentParsed


differentialIdList : Int -> DiffRecord -> EditRecord -> IdListPacket
differentialIdList seed diffRecord editRecord =
    let
        ii =
            List.length diffRecord.commonInitialSegment

        it =
            List.length diffRecord.commonTerminalSegment

        ns =
            List.length diffRecord.middleSegmentInSource

        nt =
            List.length diffRecord.middleSegmentInTarget

        idListInitial =
            List.take ii editRecord.idList

        idListMiddle =
            List.range (ii + 1) (ii + nt) |> List.map (prefixer seed)

        idListTerminal =
            List.drop (ii + ns) editRecord.idList

        idList =
            idListInitial ++ idListMiddle ++ idListTerminal

        ( newIdsStart, newIdsEnd ) =
            if nt == 0 then
                ( Nothing, Nothing )

            else
                ( Just ii, Just (ii + nt - 1) )
    in
    { idList = idList
    , newIdsStart = newIdsStart
    , newIdsEnd = newIdsEnd
    }


freshIdList : Int -> EditRecord -> IdListPacket
freshIdList seed editRecord =
    let
        newIdsStart =
            0

        newIdsEnd =
            List.length editRecord.paragraphs - 1

        idList =
            List.range newIdsStart newIdsEnd |> List.map (prefixer seed)
    in
    { idList = idList
    , newIdsStart = Just newIdsStart
    , newIdsEnd = Just newIdsEnd
    }
