module ParserUtils exposing
  ( lookAhead
  , try
  , optional
  , guard
  , token
  , inside
  , char
  , ParserI
  , getPos
  , trackInfo
  , untrackInfo
  , showError
  )

import Pos exposing (..)
import Info exposing (..)

import Parser exposing (..)
import Parser.LowLevel as LL

--------------------------------------------------------------------------------
-- General
--------------------------------------------------------------------------------

lookAhead : Parser a -> Parser a
lookAhead parser =
  let
    getResult =
      succeed
        ( \offset source ->
            let
              remainingCode =
                String.dropLeft offset source
            in
              run parser remainingCode
        )
        |= LL.getOffset
        |= LL.getSource
  in
    getResult
      |> andThen
           ( \result ->
               case result of
                 Ok x ->
                   -- Return the result without consuming input
                   succeed x

                 Err _ ->
                   -- Consume input and fail (we know it will fail)
                   parser
           )

try : Parser a -> Parser a
try parser =
  delayedCommitMap always parser (succeed ())

optional : Parser a -> Parser (Maybe a)
optional parser =
  oneOf
    [ map Just parser
    , succeed Nothing
    ]

guard : String -> Bool -> Parser ()
guard failReason pred =
  if pred then (succeed ()) else (fail failReason)

token : String -> a -> Parser a
token text val =
  map (\_ -> val) (keyword text)

keepUntil : String -> Parser String
keepUntil endString =
  let
    endLength =
      String.length endString
  in
    oneOf
      [ ignoreUntil endString
          |> source
          |> map (String.dropRight endLength)
      , succeed identity
          |. keep zeroOrMore (\_ -> True)
          |= fail ("expecting closing string '" ++ endString ++ "'")
      ]

inside : String -> Parser String
inside delimiter =
  succeed identity
    |. symbol delimiter
    |= keepUntil delimiter

char : Parser Char
char =
  map
    ( String.uncons >>
      Maybe.withDefault ('_', "") >>
      Tuple.first
    )
    ( keep (Exactly 1) (always True)
    )

--------------------------------------------------------------------------------
-- Parser With Info
--------------------------------------------------------------------------------

type alias ParserI a = Parser (WithInfo a)

getPos : Parser Pos
getPos =
  map posFromRowCol LL.getPosition

trackInfo : Parser a -> ParserI a
trackInfo p =
  delayedCommitMap
    ( \start (a, end) ->
        withInfo a start end
    )
    getPos
    ( succeed (,)
        |= p
        |= getPos
    )

untrackInfo : ParserI a -> Parser a
untrackInfo =
  map (.val)

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

showIndentedProblem : Int -> Problem -> String
showIndentedProblem n prob =
  let
    indent =
      String.repeat (2 * n) " "
  in
    case prob of
      BadOneOf probs ->
        indent ++ "One of:\n" ++
          String.concat (List.map (showIndentedProblem (n + 1)) probs)
      BadInt ->
        indent ++ "Bad integer value\n"
      BadFloat ->
        indent ++ "Bad float value\n"
      BadRepeat ->
        indent ++ "Parse of zero-length input indefinitely\n"
      ExpectingEnd ->
        indent ++ "Expecting end\n"
      ExpectingSymbol s ->
        indent ++ "Expecting symbol '" ++ s ++ "'\n"
      ExpectingKeyword s ->
        indent ++ "Expecting keyword '" ++ s ++ "'\n"
      ExpectingVariable ->
        indent ++ "Expecting variable\n"
      ExpectingClosing s ->
        indent ++ "Expecting closing string '" ++ s ++ "'\n"
      Fail s ->
        indent ++ "Parser failure: " ++ s ++ "\n"

showError : Error -> String
showError err =
  let
    prettyError =
      let
        sourceLines =
          String.lines err.source
        problemLine =
          List.head (List.drop (err.row - 1) sourceLines)
        arrow =
          (String.repeat (err.col - 1) " ") ++ "^"
      in
        case problemLine of
          Just line ->
            line ++ "\n" ++ arrow ++ "\n\n"
          Nothing ->
            ""
    showContext c =
      "  (row: " ++ (toString c.row) ++", col: " ++ (toString c.col)
      ++ ") Error while parsing '" ++ c.description ++ "'\n"
    deepestContext =
      case List.head err.context of
        Just c ->
          "Error while parsing '" ++ c.description ++ "':\n"
        Nothing ->
          ""
  in
    "[Parser Error]\n\n" ++
      deepestContext ++ "\n" ++
      prettyError ++
    "Position\n" ++
    "========\n" ++
    "  Row: " ++ (toString err.row) ++ "\n" ++
    "  Col: " ++ (toString err.col) ++ "\n\n" ++
    "Problem\n" ++
    "=======\n" ++
      (showIndentedProblem 1 err.problem) ++ "\n" ++
    "Context Stack\n" ++
    "=============\n" ++
      (String.concat <| List.map showContext err.context) ++ "\n\n"
