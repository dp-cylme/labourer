{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

module Pusher where

import Network.Google.Logging.Types

import Data.Scientific (fromFloatDigits)
import Data.Bifunctor (second)
import Data.Bits (shiftR, xor, (.&.))
import Data.Word (Word32)
import GHC.Int (Int32, Int64)
import Data.Time (UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Maybe (fromMaybe)
import Data.ProtoLens.Encoding (decodeMessage)
import GHC.Generics (Generic)
import Network.Wai
       (Application, rawPathInfo, responseLBS, Request, Response,
        lazyRequestBody)
import Network.HTTP.Types.Status
       (status404, status400, status422, status204)
import Data.Aeson (eitherDecode, FromJSON)
import Data.Text (Text)
import Network.Google.PubSub (PubsubMessage, pmData)
import Control.Lens ((^.), (.~), (&), (^?))
import Control.Monad.Log (Handler)

import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import qualified Data.ByteString.Lazy.Char8 as BSLC8
import qualified Proto.CommonLogRep as ProtoBuf
import qualified Proto.Timestamp as ProtoBuf
import qualified Proto.Struct as ProtoBuf
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Map.Strict as Map
import qualified Data.Vector as Vector


-- | Push request body
-- https://cloud.google.com/pubsub/docs/subscriber#receive
data PushMessage = PushMessage
    { message :: PubsubMessage
    , subscription :: Text
    } deriving (Generic)

instance FromJSON PushMessage


app :: Handler IO LogEntry -> Application
app logger request respond =
    case rawPathInfo request of
        "/push" -> pusher logger request >>= respond
        _ ->
            respond
                (responseLBS
                     status404
                     [("Content-Type", "plain/text")]
                     "not found - 404")

pusher :: Handler IO LogEntry -> Request -> IO Response
pusher logger request =
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
                 case decodeMessage (fromMaybe "" ((message res) ^. pmData)) :: Either String ProtoBuf.LogEntry of
                     Left err ->
                         return
                             (responseLBS
                                  status422
                                  [("Content-Type", "plain/text")]
                                  (BSLC8.pack err))
                     Right res' ->
                         logger ( localiso res' ) >>
                         return
                             (responseLBS
                                  status204
                                  [("Content-Type", "plain/text")]
                                  "ok")


localiso :: ProtoBuf.LogEntry -> LogEntry
localiso le =
    ((((((((logEntry & leJSONPayload .~ (jsonpayload' <$> le ^? ProtoBuf.jsonpayload))
                     & leOperation .~ (operation' <$> le ^? ProtoBuf.operation))
                     & leLabels .~ ((logEntryLabels . HashMap.fromList . Map.toList) <$> le ^? ProtoBuf.labels))
                     & leHTTPRequest .~ (httprequest' <$> le ^? ProtoBuf.httprequest))
                     & leSeverity .~ (showSeverity <$> le ^? ProtoBuf.severity))
                     & leTimestamp .~ (showTimestamp <$> (le ^? ProtoBuf.timestamp)))
                     & leResource .~ (resource' <$> (le ^? ProtoBuf.resource)))
                     & leLogName .~ (le ^? ProtoBuf.logname))


jsonpayload' :: ProtoBuf.Struct -> LogEntryJSONPayload
jsonpayload' jsonstruct =
    (logEntryJSONPayload
         (fromProtoBufStructToJson jsonstruct))

operation' :: ProtoBuf.LogEntryOperation -> LogEntryOperation
operation' oprtn =
    ((((logEntryOperation & leoLast .~ (oprtn ^? ProtoBuf.last))
                          & leoFirst .~ (oprtn ^? ProtoBuf.first))
                          & leoProducer .~ (oprtn ^? ProtoBuf.producer))
                          & leoId .~ (oprtn ^? ProtoBuf.id))

httprequest' :: ProtoBuf.HttpRequest -> HTTPRequest
httprequest' httpr =
    ((((((((((((hTTPRequest & httprCacheValidatedWithOriginServer .~ (httpr ^? ProtoBuf.cachevalidatewithoriginserver))
                            & httprCacheHit .~ (httpr ^? ProtoBuf.cachehit))
                            & httprCacheLookup .~ (httpr ^? ProtoBuf.cachelookup))
                            & httprReferer .~ (httpr ^? ProtoBuf.referer))
                            & httprRemoteIP .~ (httpr ^? ProtoBuf.remoteip))
                            & httprUserAgent .~ (httpr ^? ProtoBuf.useragent))
                            & httprResponseSize .~ (fromTextToInt64 <$> httpr ^? ProtoBuf.responsesize))
                            & httprRequestMethod .~ (httpr ^? ProtoBuf.requestmethod))
                            & httprRequestSize .~ (fromTextToInt64 <$> httpr ^? ProtoBuf.requestsize))
                            & httprCacheFillBytes .~ (fromTextToInt64 <$> httpr ^? ProtoBuf.cachefillbytes))
                            & httprRequestURL .~ (httpr ^? ProtoBuf.requesturl))
                            & httprStatus .~ (zzDecode32 <$> (httpr ^? ProtoBuf.status)))

resource' :: ProtoBuf.MonitoredResource -> MonitoredResource
resource' res =
    let labels' =
            case res ^? ProtoBuf.labels of
                Nothing -> Nothing
                Just res' ->
                    Just
                        (monitoredResourceLabels
                             (HashMap.fromList (Map.toList res')))
    in ((monitoredResource & mrType .~ (res ^? ProtoBuf.type'))
                           & mrLabels .~ labels')

fromTimestampToUTCTime :: ProtoBuf.Timestamp -> UTCTime
fromTimestampToUTCTime tmstp =
    posixSecondsToUTCTime
        (fromInteger (fromIntegral (tmstp ^. ProtoBuf.seconds)))

-- | A timestamp in RFC3339 UTC "Zulu" format, accurate to nanoseconds.
-- Example: "2014-10-02T15:01:23.045123456Z".
showTimestamp :: ProtoBuf.Timestamp -> UTCTime
showTimestamp =
    fromTimestampToUTCTime

showSeverity :: ProtoBuf.LogSeverity -> LogEntrySeverity
showSeverity =
    \case
        ProtoBuf.DEFAULT -> Default
        ProtoBuf.DEBUG -> Debug
        ProtoBuf.INFO -> Info
        ProtoBuf.NOTICE -> Notice
        ProtoBuf.WARNING -> Warning
        ProtoBuf.ERROR -> Error'
        ProtoBuf.CRITICAL -> Critical
        ProtoBuf.ALERT -> Alert
        ProtoBuf.EMERGENCY -> Emergency


-- | I took from
-- <https://www.stackage.org/haddock/lts-7.4/protobuf-0.2.1.1/src/Data.ProtocolBuffers.Wire.html#zzDecode32 protobuf>
-- see where find this solution them ;)
zzDecode32 :: Word32 -> Int32
zzDecode32 w =
    fromIntegral (w `shiftR` 1) `xor` negate (fromIntegral (w .&. 1))


fromTextToInt64 :: Text -> Int64
fromTextToInt64 = read . Text.unpack

fromProtoBufStructValueToAesonValue :: ProtoBuf.Value -> Aeson.Value
fromProtoBufStructValueToAesonValue value =
    case value ^? ProtoBuf.numberValue of
        Just num -> Aeson.Number (fromFloatDigits num)
        Nothing ->
            case value ^? ProtoBuf.stringValue of
                Just str -> Aeson.String str
                Nothing ->
                    case value ^? ProtoBuf.boolValue of
                        Just bln -> Aeson.Bool bln
                        Nothing ->
                            case value ^? ProtoBuf.structValue of
                                Just obj ->
                                    Aeson.Object (fromProtoBufStructToJson obj)
                                Nothing ->
                                    case value ^? ProtoBuf.listValue of
                                        Just arr ->
                                            Aeson.Array
                                                (Vector.fromList
                                                     (map
                                                          fromProtoBufStructValueToAesonValue
                                                          (arr ^.
                                                           ProtoBuf.values)))
                                        Nothing ->
                                            case value ^? ProtoBuf.nullValue of
                                                Just _ -> Aeson.Null
                                                Nothing -> Aeson.Null

fromProtoBufStructToJson :: ProtoBuf.Struct -> HashMap.HashMap Text Aeson.Value
fromProtoBufStructToJson jsonstruct =
    HashMap.fromList
        (map
             (second fromProtoBufStructValueToAesonValue)
             (Map.toList (jsonstruct ^. ProtoBuf.fields)))
