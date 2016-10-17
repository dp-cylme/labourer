{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Pusher where

import Data.Maybe (fromMaybe)
import Data.ProtoLens.Encoding (decodeMessage)
import GHC.Generics (Generic)
import Network.Wai
       (Application, rawPathInfo, responseLBS, Request, Response, lazyRequestBody)
import Network.HTTP.Types.Status (status404, status400, status422, status204)
import Data.Aeson (eitherDecode, FromJSON)
import Data.Text (Text)
import Network.Google.PubSub (PubsubMessage, pmData)
import Control.Lens ((^.))
import Proto.InnerLogRep (LogRep)

import qualified Data.ByteString.Lazy.Char8 as BSLC8


-- | Push request body
-- https://cloud.google.com/pubsub/docs/subscriber#receive
data PushMessage = PushMessage
    { message :: PubsubMessage
    , subscription :: Text
    } deriving (Generic)

instance FromJSON PushMessage


app :: Application
app request respond =
    case rawPathInfo request of
        "/push" -> pusher request >>= respond
        _ ->
            respond
                (responseLBS
                     status404
                     [("Content-Type", "plain/text")]
                     "not found - 404")

pusher :: Request -> IO Response
pusher request =
    lazyRequestBody request >>=
    \body ->
         case eitherDecode body :: Either String PushMessage of
             Left err ->
                 return
                     (responseLBS
                          status400
                          [("Content-Type", "plain/text")]
                          (BSLC8.pack err))
             Right res ->
                 case decodeMessage (fromMaybe "" ((message res) ^. pmData)) :: Either String LogRep of
                     Left err ->
                         return
                             (responseLBS
                                  status422
                                  [("Content-Type", "plain/text")]
                                  (BSLC8.pack err))
                     Right res' ->
                         return
                             (responseLBS
                                  status204
                                  [("Content-Type", "plain/text")]
                                  "ok")
