{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DataKinds #-}

module GooglePubSub where

import Control.Retry
       (defaultLogMsg, exponentialBackoff, logRetries, recovering)
import Data.Text (Text)
import Network.Google (Error(..), runResourceT, runGoogle, send, Env)
import Network.Google.PubSub
       (projectsSubscriptionsCreate, subscription, sTopic, sName,
        sPushConfig, pushConfig, pcPushEndpoint)
import Control.Lens ((&), (.~))


registerSubscription :: Env '["https://www.googleapis.com/auth/pubsub"]
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
