module MeenyLatex.FastExportToLatex exposing (export)

{-| This module is for quickly preparing latex for export.


# API

@docs export

-}

import MeenyLatex.JoinStrings as JoinStrings
import MeenyLatex.Paragraph as Paragraph
import MeenyLatex.RenderLatexForExport as RLE


{-| Tranform MiniLatex text into Latex text.
-}
export : String -> String
export sourceText =
    sourceText
        |> Paragraph.logicalParagraphify
        |> List.map processParagraph
        |> List.map (\par -> par ++ "\n\n")
        |> JoinStrings.joinList


processParagraph : String -> String
processParagraph par =
    let
        prefix =
            String.left 14 par

        signature =
            if String.left 6 prefix == "\\begin" then
                String.dropLeft 7 prefix |> String.dropRight 1
            else if String.contains "\\code" par then
                "code"
            else if String.contains "\\href" par then
                "href"
            else
                String.left 6 prefix
    in
        case signature of
            "\\image" ->
                RLE.renderLatexForExport par

            "listin" ->
                RLE.renderLatexForExport par

            "code" ->
                RLE.renderLatexForExport par

            "href" ->
                RLE.renderLatexForExport par

            "usefor" ->
                RLE.renderLatexForExport par

            _ ->
                RLE.renderLatexForExport par
