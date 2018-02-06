module ElmUnparser exposing
  ( unparse
  , unparsePattern
  )

import Lang exposing (..)
import ElmLang
import ElmParser
import BinaryOperatorParser
import Utils

unparseWD : WidgetDecl -> String
unparseWD wd =
  let strHidden bool = if bool then ",\"hidden\"" else "" in
  case wd.val of
    NoWidgetDecl        -> ""
    IntSlider a tok b _ hidden ->
      "{" ++ toString a.val ++ tok.val ++ toString b.val ++ strHidden hidden ++ "}"
    NumSlider a tok b _ hidden ->
      "{" ++ toString a.val ++ tok.val ++ toString b.val ++ strHidden hidden ++ "}"

unparseBaseValue : EBaseVal -> String
unparseBaseValue ebv =
  case ebv of
    EBool b ->
      if b then "True" else "False"

    EString quoteChar text ->
      quoteChar ++ text ++ quoteChar

    ENull ->
      "null"

unparsePattern : Pat -> String
unparsePattern p =
  case p.val.p__ of
    PVar wsBefore identifier widgetDeclaration ->
      wsBefore.val
        ++ identifier

    PConst wsBefore num ->
      wsBefore.val
        ++ toString num

    PBase wsBefore baseValue ->
      wsBefore.val
        ++ unparseBaseValue baseValue

    PParens wsBefore pat wsBeforeEnd ->
      wsBefore.val
        ++ "("
        ++ unparsePattern pat
        ++ wsBeforeEnd.val
        ++ ")"

    PList wsBefore members _ Nothing wsBeforeEnd ->
      wsBefore.val
        ++ "["
        ++ String.join "," (List.map unparsePattern members)
        ++ wsBeforeEnd.val
        ++ "]"

    PList wsBefore [head] wsMiddle (Just tail) wsBeforeEnd ->
      wsBefore.val -- Should be empty
        ++ wrapPatternWithParensIfNeeded p head (unparsePattern head)
        ++ wsMiddle.val
        ++ "::"
        ++ wrapPatternWithParensIfNeeded p tail (unparsePattern tail)
        ++ wsBeforeEnd.val -- Should be empty

    PList wsBefore (head::headTail) wsMiddle (Just tail) wsBeforeEnd ->
      unparsePattern <| replaceP__ p <| PList wsBefore [head] wsMiddle (Just (replaceP__ p <| PList wsBefore headTail wsMiddle (Just tail) wsBeforeEnd)) wsBeforeEnd

    PList _ [] wsMiddle (Just tail) _ ->
      unparsePattern tail

    PAs wsName name wsBeforeAs pat ->
      wrapPatternWithParensIfNeeded p pat (unparsePattern pat)
        ++ wsBeforeAs.val
        ++ "as"
        ++ wsName.val
        ++ name

-- TODO
unparseType : Type -> String
unparseType tipe =
  case tipe.val of
    TNum ws                   -> ws.val ++ "Num"
    TBool ws                  -> ws.val ++ "Bool"
    TString ws                -> ws.val ++ "String"
    TNull ws                  -> ws.val ++ "Null"
    TList ws1 tipe ws2        -> ws1.val ++ "(List" ++ (unparseType tipe) ++ ws2.val ++ ")"
    TDict ws1 tipe1 tipe2 ws2 -> ws1.val ++ "(Dict" ++ (unparseType tipe1) ++ (unparseType tipe2) ++ ws2.val ++ ")"
    TTuple ws1 typeList ws2 maybeRestType ws3 ->
      case maybeRestType of
        Just restType -> ws1.val ++ "[" ++ (String.concat (List.map unparseType typeList)) ++ ws2.val ++ "|" ++ (unparseType restType) ++ ws3.val ++ "]"
        Nothing       -> ws1.val ++ "[" ++ (String.concat (List.map unparseType typeList)) ++ ws3.val ++ "]"
    TArrow ws1 typeList ws2 -> ws1.val ++ "(->" ++ (String.concat (List.map unparseType typeList)) ++ ws2.val ++ ")"
    TUnion ws1 typeList ws2 -> ws1.val ++ "(union" ++ (String.concat (List.map unparseType typeList)) ++ ws2.val ++ ")"
    TNamed ws1 "Num"        -> ws1.val ++ "Bad_NUM"
    TNamed ws1 "Bool"       -> ws1.val ++ "Bad_BOOL"
    TNamed ws1 "String"     -> ws1.val ++ "Bad_STRING"
    TNamed ws1 "Null"       -> ws1.val ++ "Bad_NULL"
    TNamed ws1 ident        -> ws1.val ++ ident
    TVar ws1 ident          -> ws1.val ++ ident
    TWildcard ws            -> ws.val ++ "_"
    TForall ws1 typeVars tipe1 ws2 ->
      let strVar (ws,x) = ws.val ++ x in
      let sVars =
        case typeVars of
          One var             -> strVar var
          Many ws1_ vars ws2_ -> ws1_.val ++ Utils.parens (String.concat (List.map strVar vars) ++ ws2_.val)
      in
      ws1.val ++ Utils.parens ("forall" ++ sVars ++ unparseType tipe1 ++ ws2.val)

unparseOp : Op -> String
unparseOp op =
  case op.val of
    Pi ->
      "pi"
    DictEmpty ->
      "empty"
    Cos ->
      "cos"
    Sin ->
      "sin"
    ArcCos ->
      "arccos"
    ArcSin ->
      "arcsin"
    Floor ->
      "floor"
    Ceil ->
      "ceiling"
    Round ->
      "round"
    ToStr ->
      "toString"
    Sqrt ->
      "sqrt"
    Explode ->
      "explode"
    Plus ->
      "+"
    Minus ->
      "-"
    Mult ->
      "*"
    Div ->
      "/"
    Lt ->
      "<"
    Eq ->
      "=="
    Mod ->
      "mod"
    Pow ->
      "pow"
    ArcTan2 ->
      "arctan2"
    DictInsert ->
      "insert"
    DictGet ->
      "get"
    DictRemove ->
      "remove"
    DebugLog ->
      "debug"
    NoWidgets ->
      "noWidgets"

unparseBranch : Branch -> String
unparseBranch branch =
  case branch.val of
    Branch_ wsBefore p e _ ->
      wsBefore.val
        ++ unparsePattern p
        ++ " ->"
        ++ unparse e
        ++ ";"

unparse : Exp -> String
unparse e =
  case e.val.e__ of
    EConst wsBefore num (_, frozen, _) wd ->
      wsBefore.val
        ++ toString num
        ++ frozen
        ++ unparseWD wd

    EBase wsBefore baseValue ->
      wsBefore.val
        ++ unparseBaseValue baseValue

    EVar wsBefore identifier ->
      wsBefore.val
        ++ identifier

    EFun wsBefore parameters body _ ->
      wsBefore.val
        ++ "\\"
        ++ String.concat (List.map unparsePattern parameters)
        ++ " ->"
        ++ unparse body

    EApp wsBefore function arguments _ ->
      -- NOTE: to help with converting Little to Elm
      let unparseArg e =
        case e.val.e__ of
          EApp ws1 f args ws2 ->
            ws1.val
              ++ "("
              ++ unparse (replaceE__ e (EApp { ws1 | val = "" } f args ws2))
              ++ ")"
          EOp ws1 f args ws2 ->
            ws1.val
              ++ "("
              ++ unparse (replaceE__ e (EOp { ws1 | val = "" } f args ws2))
              ++ ")"
          _ ->
            unparse e
      in
      wsBefore.val
        ++ unparse function
        -- NOTE: to help with converting Little to Elm
        -- ++ String.concat (List.map unparse arguments)
        ++ String.concat (List.map unparseArg arguments)

    EOp wsBefore op arguments _ ->
      let
        default =
          wsBefore.val
            ++ unparseOp op
            ++ String.concat (List.map unparse arguments)
      in
        if ElmLang.isInfixOperator op then
          case arguments of
            [ left, right ] ->
              wrapWithParensIfNeeded e left (unparse left)
                ++ wsBefore.val
                ++ unparseOp op
                ++ wrapWithParensIfNeeded e right (unparse right)
            _ ->
              default
        else
          default

    EList wsBefore members wsmiddle Nothing wsBeforeEnd ->
      wsBefore.val
        ++ "["
        ++ String.join "," (List.map unparse members)
        ++ wsBeforeEnd.val
        ++ "]"

    EList wsBefore [head] wsmiddle (Just tail) wsBeforeEnd ->
      wsBefore.val -- Should be empty
        ++ wrapWithParensIfNeeded e head (unparse head)
        ++ wsmiddle.val
        ++ "::"
        ++ wrapWithParensIfNeeded e tail (unparse tail)
        ++ wsBeforeEnd.val -- Should be empty

    -- Obsolete, remove whenever we are sure that there are no mutliple cons anymore.
    EList wsBefore (head::headtail) wsmiddle (Just tail) wsBeforeEnd ->
      unparse <| replaceE__ e <| EList wsBefore [head] wsmiddle (Just <| replaceE__ e <| EList wsBefore headtail wsmiddle (Just tail) wsBeforeEnd) wsBeforeEnd

    EList wsBefore [] wsMiddle (Just tail) wsBeforeEnd ->
      unparse tail

    EIf wsBefore condition trueBranch falseBranch _ ->
      wsBefore.val
        ++ "if"
        ++ unparse condition
        ++ " then"
        ++ unparse trueBranch
        ++ " else"
        ++ unparse falseBranch

    ECase wsBefore examinedExpression branches _ ->
      wsBefore.val
        ++ "case"
        ++ unparse examinedExpression
        ++ " of"
        ++ String.concat (List.map unparseBranch branches)

    ELet wsBefore letKind isRec name binding_ body wsBeforeSemicolon ->
      let
        (parameters, binding) =
          case binding_.val.e__ of
            EFun _ parameters functionBinding _ ->
              (parameters, functionBinding)

            _ ->
              ([], binding_)

        strParametersDefault =
          String.concat (List.map unparsePattern parameters)

        -- NOTE: to help with converting Little to Elm
        strParameters =
          case (parameters, String.startsWith " " strParametersDefault) of
            (_::_, False) -> " " ++ strParametersDefault
            _             -> strParametersDefault
      in
      case letKind of
        Let ->
          wsBefore.val
            ++ (if isRec then "letrec" else "let")
            ++ unparsePattern name
            -- NOTE: to help with converting Little to Elm
            -- ++ String.concat (List.map unparsePattern parameters)
            ++ strParameters
            ++ " ="
            ++ unparse binding
            ++ " in"
            ++ unparse body

        Def ->
          wsBefore.val
            -- NOTE: to help with converting Little to Elm
            -- ++ unparsePattern name
            ++ ( let
                   strName =
                     unparsePattern name
                 in
                   if String.startsWith " " strName
                     then String.dropLeft 1 strName
                     else strName
               )
            -- NOTE: to help with converting Little to Elm
            -- ++ String.concat (List.map unparsePattern parameters)
            ++ strParameters
            ++ " ="
            ++ unparse binding
            ++ wsBeforeSemicolon.val
            ++ ";"
            ++ unparse body

    EComment wsBefore text expAfter ->
      wsBefore.val
        ++ "--"
        ++ text
        ++ "\n"
        ++ unparse expAfter

    EOption wsBefore option wsMid value expAfter ->
      wsBefore.val
        ++ "# "
        ++ option.val
        ++ ":"
        ++ wsMid.val
        ++ value.val
        ++ "\n"
        ++ unparse expAfter

    EParens wsBefore innerExpression wsAfter ->
      wsBefore.val
        ++ "("
        ++ unparse innerExpression
        ++ wsAfter.val
        ++ ")"

    EHole wsBefore val ->
      wsBefore.val
        ++ "??"

    Lang.EColonType wsBefore term wsBeforeColon typ wsAfter ->
      wsBefore.val
        ++ "("
        ++ unparse term
        ++ wsBeforeColon.val
        ++ ":"
        ++ unparseType typ
        ++ wsAfter.val
        ++ ")"

    Lang.ETyp _ name typ rest wsBeforeColon ->
      unparsePattern name
        ++ wsBeforeColon.val
        ++ ":"
        ++ unparseType typ
        ++ unparse rest

    Lang.ETypeAlias wsBefore pat typ rest _ ->
      wsBefore.val
        ++ "type alias"
        ++ unparsePattern pat
        ++ " ="
        ++ unparseType typ
        ++ unparse rest

    Lang.ETypeCase _ _ _ _ ->
      "{Error: typecase not yet implemented for Elm syntax}" -- TODO

getExpPrecedence: Exp -> Int
getExpPrecedence exp =
  case exp.val.e__ of
    EList _ [head] _ (Just tail) _ -> 5
    EOp _ operator _ _ ->
      case BinaryOperatorParser.getOperatorInfo (unparseOp operator) ElmParser.builtInPrecedenceTable of
        Nothing -> 10
        Just (associativity, precedence) -> precedence
    _ -> 10

wrapWithParensIfNeeded: Exp -> Exp -> String -> String
wrapWithParensIfNeeded outsideExp insideExp unparsedInsideExpr =
  if getExpPrecedence insideExp < getExpPrecedence outsideExp then "(" ++ unparsedInsideExpr ++ ")" else unparsedInsideExpr


getPatPrecedence: Pat -> Int
getPatPrecedence pat =
  case pat.val.p__ of
    PList _ _ _ (Just tail) _ ->
      case BinaryOperatorParser.getOperatorInfo "::" ElmParser.builtInPatternPrecedenceTable of
        Nothing -> 10
        Just (associativity, precedence) -> precedence
    PAs _ _ _ _ ->
      case BinaryOperatorParser.getOperatorInfo "as" ElmParser.builtInPatternPrecedenceTable of
        Nothing -> 10
        Just (associativity, precedence) -> precedence
    _ -> 10

wrapPatternWithParensIfNeeded: Pat -> Pat -> String -> String
wrapPatternWithParensIfNeeded outsidePat insidePat unparsedInsidePat =
  if getPatPrecedence insidePat < getPatPrecedence outsidePat then "(" ++ unparsedInsidePat ++ ")" else unparsedInsidePat
