module Text.LLVM.Parser where

import Text.LLVM.AST

import Data.Int (Int32)
import Text.Parsec
import Text.Parsec.String


-- Identifiers and Symbols -----------------------------------------------------

pNameChar :: Parser Char
pNameChar = letter <|> digit <|> oneOf "-$._"

pIdent :: Parser Ident
pIdent = Ident <$> (char '%' >> many1 pNameChar)

pSymbol :: Parser Symbol
pSymbol = Symbol <$> (char '@' >> many1 pNameChar)


-- Types -----------------------------------------------------------------------

pInt32 :: Parser Int32
pInt32 = read <$> many1 digit

pPrimType :: Parser PrimType
pPrimType = choice
  [ Integer <$> try (char 'i' >> pInt32)
  , FloatType <$> try pFloatType
  , try (string "label")    >> return Label
  , try (string "void")     >> return Void
  , try (string "x86mmx")   >> return X86mmx
  , try (string "metadata") >> return Metadata
  ]

pFloatType :: Parser FloatType
pFloatType = choice
  [ try (string "half")      >> return Half
  , try (string "float")     >> return Float
  , try (string "double")    >> return Double
  , try (string "fp128")     >> return Fp128
  , try (string "x86_fp80")  >> return X86_fp80
  , try (string "ppc_fp128") >> return PPC_fp128
  ]

pType :: Parser Type
pType = pType0 >>= pFunPtr
  where
    pType0 :: Parser Type
    pType0 =
      choice
      [ Alias <$> pIdent
      , brackets (pNumType Array)
      , braces (Struct <$> pTypeList)
      , angles (braces (PackedStruct <$> pTypeList) <|> spaced (pNumType Vector))
      , string "opaque" >> return Opaque
      , PrimType <$> pPrimType
      ]

    pTypeList :: Parser [Type]
    pTypeList = sepBy (spaced pType) (char ',')

    pNumType :: (Int32 -> Type -> Type) -> Parser Type
    pNumType f =
      do n <- pInt32
         spaces >> char 'x' >> spaces
         t <- pType
         return (f n t)

    pArgList :: Type -> Parser Type
    pArgList t0 = spaces >> (p1 [] <|> return (FunTy t0 [] False))
      where
        p1 ts =
          (string "..." >> spaces >> return (FunTy t0 (reverse ts) True))
          <|> (pType >>= \t -> (spaces >> p2 (t : ts)))
        p2 ts =
          (char ',' >> spaces >> p1 ts)
          <|> return (FunTy t0 (reverse ts) False)

    pFunPtr :: Type -> Parser Type
    pFunPtr t0 = pFun <|> pPtr <|> return t0
      where
        pFun = parens (pArgList t0) >>= pFunPtr
        pPtr = char '*' >> pFunPtr (PtrTo t0)

parseType :: String -> Either ParseError Type
parseType = parse (pType <* eof) "<internal>"


-- Utilities -------------------------------------------------------------------

angles :: Parser a -> Parser a
angles body = char '<' *> body <* char '>'

braces :: Parser a -> Parser a
braces body = char '{' *> body <* char '}'

brackets :: Parser a -> Parser a
brackets body = char '[' *> body <* char ']'

parens :: Parser a -> Parser a
parens body = char '(' *> body <* char ')'

spaced :: Parser a -> Parser a
spaced body = spaces *> body <* spaces
