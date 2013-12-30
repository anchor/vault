--
-- Data vault for metrics
--
-- Copyright © 2013-     Anchor Systems, Pty Ltd and Others
--
-- The code in this file, and the program it is a part of, is
-- made available to you by its authors as open source software:
-- you can redistribute it and/or modify it under the terms of
-- the BSD licence.
--

{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# OPTIONS -fno-warn-unused-imports #-}

module Vaultaire.Internal.CoreTypes
(
    Point(..),
    Value(..)
)
where

import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Map (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Word (Word32, Word64)


data Point = Point {
    origin    :: ByteString,
    source    :: Map Text Text,
    timestamp :: Word64,     -- ?
    payload   :: Value
} deriving (Eq, Show)


data Value
    = Empty
    | Numeric Int64
    | Measurement Double
    | Textual Text
    | Blob ByteString
    deriving (Eq, Show)

{-

instance Show Point where
    show x = intercalate "\n"
        [show $ source x,
         show $ timestamp x,
         case payload x of
                Empty       -> ""
                Numeric n   ->  show n
                Textual t   ->  T.unpack t
                Measurement r ->  show r
                Blob b'     -> show b']


-}
