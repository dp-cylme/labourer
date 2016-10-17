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
import Network.Wai.Middleware.RequestLogger.JSON (formatAsJSON)
import Network.Wai.Middleware.RequestLogger
       (OutputFormat(CustomOutputFormatWithDetails), mkRequestLogger,
        outputFormat)
import Data.Default (def)
import GooglePubSub (registerSubscription)
import Control.Concurrent (forkIO, threadDelay)
import Network.Google
       (newEnv, HasEnv(envScopes, envLogger), newLogger, LogLevel(Debug))
import Control.Lens ((<&>), (.~))
import Network.Google.PubSub (pubSubScope)
import System.IO (stdout)
import Options.Generic (ParseRecord, getRecord, type (<?>)(..))


data Args = Args
    { host :: Text <?> "IP address where Google PubSub will push messages"
    , topic :: Text <?> "Google PubSub topic name from messages we want"
    , subscription :: Text <?> "subscription name"
    } deriving (Generic)

instance ParseRecord Args


main :: IO ()
main = do
    args <- getRecord "Test program"
    lgr <- newLogger Debug stdout
    env <- newEnv <&> (envLogger .~ lgr) . (envScopes .~ pubSubScope)
    _ <-
        forkIO
            (threadDelay 3000 >>
             registerSubscription
                 env
                 (unHelpful (host args) <> "/push")
                 (unHelpful (topic args))
                 (unHelpful (subscription args)))
    logStdout <-
        mkRequestLogger
            def
            { outputFormat = CustomOutputFormatWithDetails formatAsJSON
            }
    run 3000 $ logStdout $ app
