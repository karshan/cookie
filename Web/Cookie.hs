{-# LANGUAGE OverloadedStrings #-}
module Web.Cookie
    ( -- * Server to client
      SetCookie (..)
    , parseSetCookie
    , renderSetCookie
      -- * Client to server
    , Cookies
    , parseCookies
    , renderCookies
      -- * Expires field
    , expiresFormat
    , formatCookieExpires
    , parseCookieExpires
    ) where

import qualified Data.ByteString as S
import qualified Data.ByteString.Char8 as S8
import Blaze.ByteString.Builder (Builder, fromByteString)
import Blaze.ByteString.Builder.Char8 (fromChar, fromString)
import Data.Monoid (mempty, mappend, mconcat)
import Data.Word (Word8)
import Data.Time (UTCTime, formatTime, parseTime)
import System.Locale (defaultTimeLocale)
import Data.Char (toLower)
import Control.Arrow (first)

type Cookies = [(S.ByteString, S.ByteString)]

-- | Decode the value of a \"Cookie\" request header into key/value pairs.
parseCookies :: S.ByteString -> Cookies
parseCookies s
  | S.null s = []
  | otherwise =
    let (x, y) = breakDiscard 59 s -- semicolon
     in parseCookie x : parseCookies y

parseCookie :: S.ByteString -> (S.ByteString, S.ByteString)
parseCookie s =
    let (key, value) = breakDiscard 61 s -- equals sign
        key' = S.dropWhile (== 32) key -- space
     in (key', value)

breakDiscard :: Word8 -> S.ByteString -> (S.ByteString, S.ByteString)
breakDiscard w s =
    let (x, y) = S.break (== w) s
     in (x, S.drop 1 y)

renderCookies :: Cookies -> Builder
renderCookies [] = mempty
renderCookies cs =
    foldr1 go $ map renderCookie cs
  where
    go x y = x `mappend` fromChar ';' `mappend` y

renderCookie :: (S.ByteString, S.ByteString) -> Builder
renderCookie (k, v) =
    fromByteString k `mappend` fromChar '=' `mappend` fromByteString v

data SetCookie = SetCookie
    { setCookieName :: S.ByteString
    , setCookieValue :: S.ByteString
    , setCookiePath :: Maybe S.ByteString
    , setCookieExpires :: Maybe UTCTime
    , setCookieDomain :: Maybe S.ByteString
    }
    deriving (Eq, Show, Read)

renderSetCookie :: SetCookie -> Builder
renderSetCookie sc = mconcat
    [ fromByteString $ setCookieName sc
    , fromChar '='
    , fromByteString $ setCookieValue sc
    , case setCookiePath sc of
        Nothing -> mempty
        Just path -> fromByteString "; path=" `mappend` fromByteString path
    , case setCookieExpires sc of
        Nothing -> mempty
        Just e -> fromByteString "; expires=" `mappend`
                  fromString (formatCookieExpires e)
    , case setCookieDomain sc of
        Nothing -> mempty
        Just d -> fromByteString "; domain=" `mappend` fromByteString d
    ]

parseSetCookie :: S.ByteString -> SetCookie
parseSetCookie a = SetCookie
    { setCookieName = key
    , setCookieValue = value
    , setCookiePath = lookup "path" pairs
    , setCookieExpires =
        lookup "expires" pairs >>= (parseCookieExpires . S8.unpack)
    , setCookieDomain = lookup "domain" pairs
    }
  where
    (key, value, b) = parsePair a
    pairs = map (first $ S8.map toLower) $ parsePairs b
    parsePair bs =
        let (k, bs') = breakDiscard 61 bs -- equals sign
            (v, bs'') = breakDiscard 59 bs' -- semicolon
         in (k, v, S.dropWhile (== 32) bs'') -- space
    parsePairs bs =
        if S.null bs
            then []
            else let (k, v, bs') = parsePair bs
                  in (k, v) : parsePairs bs'

expiresFormat :: String
expiresFormat = "%a, %d-%b-%Y %X GMT"

-- | Format a 'UTCTime' for a cookie.
formatCookieExpires :: UTCTime -> String
formatCookieExpires = formatTime defaultTimeLocale expiresFormat

parseCookieExpires :: String -> Maybe UTCTime
parseCookieExpires = parseTime defaultTimeLocale expiresFormat