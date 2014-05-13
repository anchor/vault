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

{-# LANGUAGE OverloadedStrings #-}

module Vaultaire.ContentsServer
(
    startContents,
    Operation(..),
    -- testing
    opcodeToWord64,
    handleSourceArgument,
    encodeAddressToBytes
) where

import Control.Exception
import Control.Monad.State.Strict
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as S
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HashMap
import Data.Packer
import Data.Text (Text)
import qualified Data.Text.Encoding as T
import Data.Word (Word64)
import System.Rados.Monadic

import Vaultaire.Daemon
import Vaultaire.OriginMap

--
-- Daemon implementation
--

data Operation =
    ContentsListRequest Address |
    RegisterNewAddress |
    UpdateSourceTag Address SourceDict |
    RemoveSourceTag Address SourceDict
  deriving
    (Show, Eq)


type SourceDict = HashMap Text Text

-- | Start a writer daemon, never returns.
startContents
    :: String           -- ^ Broker
    -> Maybe ByteString -- ^ Username for Ceph
    -> ByteString       -- ^ Pool name for Ceph
    -> IO ()
startContents broker user pool =
    runDaemon broker user pool $ forever $ nextMessage >>= handleRequest


handleRequest :: Message -> Daemon ()
handleRequest (Message reply o p') =
    case tryUnpacking parseOperationMessage p' of
        Left err         -> failWithString reply "Unable to parse request message" err
        Right op -> case op of
            ContentsListRequest a -> performListRequest reply o a
            RegisterNewAddress    -> performRegisterRequest reply o
            UpdateSourceTag a s   -> performUpdateRequest reply o a s
            RemoveSourceTag a s   -> performRemoveRequest reply o a s


parseOperationMessage :: Unpacking Operation
parseOperationMessage = do
    word <- getWord64LE
    case word of
        0x0 -> do
            a <- getWord64LE
            return (ContentsListRequest a)
        0x1 -> do
            return RegisterNewAddress
        0x2 -> do
            a <- getWord64LE
            s <- parseSourceDict
            return (UpdateSourceTag a s)
        0x3 -> do
            a <- getWord64LE
            s <- parseSourceDict
            return (RemoveSourceTag a s)
        _   -> fail "Illegal op code"


parseSourceDict :: Unpacking SourceDict
parseSourceDict = do
    n  <- getWord64LE
    b' <- getBytes (fromIntegral n)
    return $ handleSourceArgument b'

{-
    We could replace this with a proper parser in order to get better
    error reporting if this ever starts being a problem.
-}
handleSourceArgument :: ByteString -> SourceDict
handleSourceArgument b' =
  let
    items' = S.split ',' b'
    pairs' = map (S.split ':') items'
    pairs  = map toTag pairs'
  in
    HashMap.fromList pairs
  where
    toTag :: [ByteString] -> (Text, Text)
    toTag [k',v'] = (T.decodeUtf8 k', T.decodeUtf8 v')
    toTag _ = error "invalid source argument"


failWithString :: (Response -> Daemon ()) -> String -> SomeException -> Daemon ()
failWithString reply msg e = do
    liftIO $ putStrLn $ msg ++ "; " ++ show e
    reply (Failure (S.pack msg))


opcodeToWord64 :: Operation -> Word64
opcodeToWord64 op =
    case op of
        ContentsListRequest _ -> 0x0
        RegisterNewAddress    -> 0x1
        UpdateSourceTag _ _   -> 0x2
        RemoveSourceTag _ _   -> 0x3



performListRequest :: (Response -> Daemon ()) -> Origin -> Address -> Daemon ()
performListRequest reply o a = do
    odm <- get

    r <- liftPool $ readContentsFromVault o a
    let r' = encodeContentsToBytes r

    reply (Response r')


readContentsFromVault :: Origin -> Address -> Pool ByteString
readContentsFromVault o a = undefined
{-
    For the given address, read all the contents entries matching it. The
    latest entry is deemed most correct. Return that blob.
-}

encodeContentsToBytes = undefined


performRegisterRequest :: (Response -> Daemon ()) -> Origin -> Daemon ()
performRegisterRequest reply o = do
    a <- liftPool $ allocateNewAddressInVault o
    let r' = encodeAddressToBytes a
    reply (Response r')

allocateNewAddressInVault :: Origin -> Pool Address
allocateNewAddressInVault o = undefined
{-
    Procedure:

    1. Generate a random number.
    2. See if it's already present in Vault. If so, return 1.
    3. Write new number to Vault.
    4. Return number.

    This needs to be locked :/
-}

encodeAddressToBytes :: Address -> ByteString
encodeAddressToBytes a = runPacking 8 $ do
    putWord64LE a


performUpdateRequest
    :: (Response -> Daemon ())
    -> Origin
    -> Address
    -> SourceDict
    -> Daemon ()
performUpdateRequest reply o a s = do
    s0 <- liftPool $ retreiveSourceTagsForAddress o a

    -- elements in first map win
    let s1 = HashMap.union s s0

    liftPool $ writeSourceTagsForAddress o a s1
    reply Success

retreiveSourceTagsForAddress :: Origin -> Address -> Pool SourceDict
retreiveSourceTagsForAddress = undefined

writeSourceTagsForAddress :: Origin -> Address -> SourceDict -> Pool ()
writeSourceTagsForAddress = undefined


performRemoveRequest
    :: (Response -> Daemon ())
    -> Origin
    -> Address
    -> SourceDict
    -> Daemon ()
performRemoveRequest reply o a s = do
    s0 <- liftPool $ retreiveSourceTagsForAddress o a

    -- elements of first not existing in second
    let s1 = HashMap.difference s0 s

    liftPool $ writeSourceTagsForAddress o a s1
    reply Success
