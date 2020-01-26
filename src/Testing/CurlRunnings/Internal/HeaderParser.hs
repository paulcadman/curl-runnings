{-# LANGUAGE OverloadedStrings #-}

module Testing.CurlRunnings.Internal.HeaderParser
    (
      parseHeaders
    ) where

import           Data.Bifunctor             (Bifunctor (..))
import           Data.Char                  (isAscii)
import qualified Data.Text                  as T
import           Data.Void
import           Testing.CurlRunnings.Types
import           Text.Megaparsec
import           Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L

type Parser = Parsec Void T.Text

parseHeaders :: T.Text -> Either T.Text Headers
parseHeaders hs = let trimmed = T.strip hs in
  first (T.pack . errorBundlePretty) (Text.Megaparsec.parse parseHeaderText "" trimmed)

headerColon :: Parser T.Text
headerColon = L.symbol space ":"

headerSemiColon :: Parser T.Text
headerSemiColon = L.symbol space ";"

parseHeader :: Parser Header
parseHeader = do
  key <- takeWhileP (Just "header key") (asciiExcludingChar ':') <* headerColon
  value <- takeWhileP (Just "header value") (asciiExcludingChar ';') <* headerSemiColon
  return $ Header (T.strip key) (T.strip value) where
    asciiExcludingChar c t =  isAscii t && t /= c

parseHeaderText :: Parser Headers
parseHeaderText = HeaderSet <$> many parseHeader
