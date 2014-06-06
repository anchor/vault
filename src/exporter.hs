--
-- Data vault for metrics
--
-- Copyright © 2013-2014 Anchor Systems, Pty Ltd and Others
--
-- The code in this file, and the program it is a part of, is
-- made available to you by its authors as open source software:
-- you can redistribute it and/or modify it under the terms of
-- the BSD licence.
--

{-# LANGUAGE CPP                #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE PackageImports     #-}
{-# LANGUAGE RecordWildCards    #-}
{-# OPTIONS -fno-warn-type-defaults #-}

module Main where

import Codec.Compression.LZ4
import Control.Applicative
import qualified Control.Concurrent.Async as Async
import Control.Concurrent.Chan
import Control.Concurrent.MVar
import Control.Exception (SomeException, throw)
import Control.Monad (unless)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Binary.IEEE754 (doubleToWord)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as S
import Data.Foldable (forM_)
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HashMap
import Data.List.NonEmpty (fromList)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Data.Time.Clock
import System.Environment (getArgs)
import qualified System.Rados.Monadic as Rados
import Text.Printf

import Data.Word
import Vaultaire.Conversion.Receiver
import Vaultaire.Conversion.Transmitter
import Vaultaire.Internal.CoreTypes
import qualified Vaultaire.Persistence.BucketObject as Bucket
import qualified Vaultaire.Persistence.ContentsObject as Contents

import qualified "vaultaire" Marquise.Client as Marquise
import qualified "vaultaire" Vaultaire.Types as Vaultaire

hashSourceToAddress :: SourceDict -> Either String Vaultaire.Address
hashSourceToAddress s = do
    x <- (selectInclusions . runSourceDict) s
    (Right . Marquise.hashIdentifier) x


selectInclusions :: Map ByteString ByteString -> Either String ByteString
selectInclusions m = do
    host   <- lookup m "host"
    metric <- lookup m "metric"
    server <- lookup m "server"
    Right $ S.concat ["host:", host, ",metric:", metric, ",server:", server]
  where
    lookup :: Map ByteString ByteString -> ByteString -> Either String ByteString
    lookup m k = case Map.lookup k m of
                    Just v  -> Right v
                    Nothing -> Left ("Lookup failed mandatory field " ++ (S.unpack k))


convertSourceDict :: SourceDict -> Either String Vaultaire.SourceDict
convertSourceDict = Vaultaire.makeSourceDict . makeHashMapFromMap . filterUndesireables . runSourceDict


makeHashMapFromMap :: Map ByteString ByteString -> HashMap Text Text
makeHashMapFromMap = HashMap.fromList . map raise . Map.toList
  where
    raise :: (ByteString, ByteString) -> (Text, Text)
    raise (k,v) = (T.pack . S.unpack $ k, T.pack . S.unpack $ v)

filterUndesireables :: Map ByteString ByteString -> Map ByteString ByteString
filterUndesireables = Map.delete "origin"


main :: IO ()
main = do
    -- just one
    [origin] <- getArgs

    let Right spool = Marquise.makeSpoolName "exporter"

    Rados.runConnect (Just "vaultaire") (Rados.parseConfig "/etc/ceph/ceph.conf") $ do
        Rados.runPool "vaultaire" $ do
            let o = Origin (S.pack origin)
            let l = Contents.formObjectLabel o
            st <- Contents.readVaultObject l
            let t1 = 1393632000 --  1 March
            let t2 = 1402790400 -- 15 June
            let is = Bucket.calculateTimemarks t1 t2

            forM_ st $ \s -> do
                -- Work out address
                let a = either error id $ hashSourceToAddress s

                -- All tags, less undesirables
                let s' = either error id $ convertSourceDict s

                -- Register that source at address
                liftIO $ Marquise.withBroker "nebula" $
                    Marquise.updateSourceDict a s' >>= either throw return

                -- Process all its data points
                forM_ is $ \i -> do
                    m <- Bucket.readVaultObject o s i

                    unless (Map.null m) $ do
                        let ps = Bucket.pointsInRange t1 t2 m

                        liftIO $ forM_ ps (convertPointAndWrite spool a)


convertPointAndWrite :: Marquise.SpoolName -> Marquise.Address -> Point -> IO ()
convertPointAndWrite spool a p =
  let
    t = Marquise.TimeStamp (timestamp p)
  in
    case payload p of
        Empty           -> Marquise.sendSimple   spool a t 0
        Numeric n       -> Marquise.sendSimple   spool a t (fromIntegral n)
        Measurement r   -> Marquise.sendSimple   spool a t (doubleToWord r)
        Textual s       -> Marquise.sendExtended spool a t (T.encodeUtf8 s)     -- DANGER partial
        Blob b          -> Marquise.sendExtended spool a t b
