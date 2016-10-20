{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Main where

import Data.Monoid ((<>))
import Pusher (app)
import Data.Text (Text)
import GHC.Generics (Generic)
import Network.Wai.Handler.Warp (run)
import GooglePubSub (registerSubscription)
import Control.Concurrent (forkIO, threadDelay)
import Network.Google
       (newEnv, HasEnv(envScopes, envLogger), newLogger, LogLevel(Debug), (!))
import Control.Lens ((<&>), (.~), (&))
import Network.Google.PubSub (pubSubScope)
import Network.Google.Logging
       (loggingWriteScope, monitoredResource, mrType, mrLabels,
        monitoredResourceLabels)
import System.IO (stdout)
import Options.Generic (ParseRecord, getRecord, type (<?>)(..))
import Control.Monad.Log.Handler (withGoogleLoggingHandler)
import Control.Monad.Log (defaultBatchingOptions, BatchingOptions(..))
import Network.Wai.Logger.GoogleLogging (loggerMiddleware)

import qualified Data.HashMap.Strict as HashMap


data Args = Args
    { host :: Text <?> "IP address where Google PubSub will push messages"
    , topic :: Text <?> "Google PubSub topic name from messages we want"
    , subscription :: Text <?> "subscription name"
    , projectid :: Text <?> "Project ID, used in log name"
    , instanceId :: Text <?> "Instance ID"
    , zone :: Text <?> "zone where instance located"
    } deriving (Generic)

instance ParseRecord Args


main :: IO ()
main = do
    args <-
        getRecord
            "labourer - web service for extracting logs from Google PubSub and send to Google Logging"
    lgr <- newLogger Debug stdout
    env <-
        newEnv <&> (envScopes .~ (loggingWriteScope ! pubSubScope)) .
        (envLogger .~ lgr)
    _ <-
        forkIO
            (threadDelay 3000 >>
             registerSubscription
                 env
                 (unHelpful (host args) <> "/push")
                 (unHelpful (topic args))
                 (unHelpful (subscription args)))
    withGoogleLoggingHandler
        (defaultBatchingOptions
         { flushMaxDelay = 10 * 1000000
         , flushMaxQueueSize = 128
         })
        env
        (Just ("projects/" <> (unHelpful (projectid args)) <> "/logs/labourer"))
        (Just
             ((monitoredResource & mrLabels .~
               (Just
                    (monitoredResourceLabels
                         (HashMap.fromList
                              ([ ("instanceId", (unHelpful (instanceId args)))
                               , ("zone", (unHelpful (zone args)))]))))) &
              mrType .~
              (Just "gce_instance")))
        Nothing $
        \wailogger ->
             withGoogleLoggingHandler
                 (defaultBatchingOptions
                  { flushMaxDelay = 4 * 1000000
                  })
                 env
                 Nothing
                 Nothing
                 Nothing $
             \logger ->
                  run 3000 $ loggerMiddleware wailogger $ app logger
