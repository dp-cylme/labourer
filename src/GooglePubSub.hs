{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DataKinds #-}

module GooglePubSub where

import Data.Text (Text)
import Control.Retry
       (defaultLogMsg, exponentialBackoff, logRetries, recovering)
import Network.Google (Error(..), runResourceT, runGoogle, send)
import Network.Google.Env (HasEnv)
import Network.Google.Auth.Scope (HasScope', AllowScopes)
import Network.Google.PubSub
       (projectsSubscriptionsCreate, subscription, sTopic, sName,
        sPushConfig, pushConfig, pcPushEndpoint)
import Control.Lens ((&), (.~))


registerSubscription
  :: (HasScope'
        s
        '["https://www.googleapis.com/auth/cloud-platform",
          "https://www.googleapis.com/auth/pubsub"]
      ~
      'True,
      AllowScopes s,
      HasEnv s r) =>
     r
     -> Text
     -> Text
     -> Text
     -> IO ()
registerSubscription env path topicName subscriptionName = do
    _ <-
        recovering
            (exponentialBackoff 15)
            [ logRetries
                  (\(TransportError _) ->
                        return False)
                  (\b e rs ->
                        print (defaultLogMsg b e rs))]
            (\_ ->
                  runResourceT
                      (runGoogle
                           env
                           (send
                                (projectsSubscriptionsCreate
                                     (subscription & (sTopic .~ Just topicName) .
                                      (sName .~ Just subscriptionName) .
                                      (sPushConfig .~
                                       Just
                                           (pushConfig & pcPushEndpoint .~
                                            Just path)))
                                     subscriptionName))))
    return ()
